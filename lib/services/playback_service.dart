import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/book.dart';
import 'progress_store.dart';

/// App-wide player. Lives for the whole app (not just the player screen),
/// so audio keeps playing when you leave the screen or lock the phone.
///
/// The UI talks to this class. The lock screen / notification / headset
/// buttons reach it through TomecastAudioHandler.
class PlaybackService extends ChangeNotifier {
  PlaybackService._();
  static final instance = PlaybackService._();

  final AudioPlayer player = AudioPlayer();

  Book? _book;
  int _fileIndex = 0;
  bool _changingFile = false;
  bool _listening = false;
  String? _error;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  Book? get book => _book;
  int get fileIndex => _fileIndex;
  String? get error => _error;
  double get speed => player.speed;
  bool get isFirstFile => _fileIndex == 0;
  bool get isLastFile => _book == null || _fileIndex == _book!.files.length - 1;
  String get currentFilePath => _book!.files[_fileIndex];

  bool get isPlaying =>
      player.playing && player.processingState != ProcessingState.completed;

  /// e.g. 1.9 → "Read 1.9 of 23 files"
  double get filesRead {
    final dur = player.duration;
    if (dur == null || dur.inMilliseconds == 0) return _fileIndex.toDouble();
    final frac =
        (player.position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
    return _fileIndex + frac;
  }

  // ---------------- Opening a book ----------------

  Future<void> openBook(Book book) async {
    if (_book?.id == book.id) return; // already loaded

    if (_book != null) {
      await player.pause();
      await save();
    }

    _startListening();
    _book = book;
    _fileIndex = book.currentFileIndex.clamp(0, book.files.length - 1);
    _error = null;
    notifyListeners();

    await player.setSpeed(book.speed);
    await _loadFile(_fileIndex, book.position);
  }

  void _startListening() {
    if (_listening) return;
    _listening = true;

    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _onFileCompleted();
      }
      notifyListeners();
    });

    // Auto-save every 5 seconds while playing.
    player.positionStream.listen((_) {
      if (player.playing &&
          DateTime.now().difference(_lastSave).inSeconds >= 5) {
        save();
      }
    });
  }

  /// Loads file [index] at [position]. Returns the file's length.
  /// If the player was playing, it keeps playing the new file.
  Future<Duration?> _loadFile(int index, Duration position) async {
    final book = _book!;
    _changingFile = true;
    _fileIndex = index;
    try {
      final dur = await player.setFilePath(
        book.files[index],
        initialPosition: position,
      );
      _error = null;
      return dur;
    } catch (e) {
      _error = 'Could not open this file:\n${book.files[index]}\n\n$e';
      return null;
    } finally {
      _changingFile = false;
      notifyListeners();
    }
  }

  Future<void> _onFileCompleted() async {
    if (_changingFile || _book == null) return; // ignore duplicate events

    if (isLastFile) {
      _book!.finished = true;
      await player.pause();
      cancelSleepTimer();
      await save();
      notifyListeners();
      return;
    }

    if (_sleepAtEndOfFile) {
      // Sleep timer "end of file": stop here, ready at the next file.
      await player.pause();
      await _loadFile(_fileIndex + 1, Duration.zero);
      cancelSleepTimer();
      await save();
      return;
    }

    await _loadFile(_fileIndex + 1, Duration.zero);
    player.play();
    await save();
  }

  // ---------------- Controls ----------------

  Future<void> play() async {
    if (_book == null) return;
    // Book finished and you press play again → start over.
    if (player.processingState == ProcessingState.completed) {
      _book!.finished = false;
      await _loadFile(0, Duration.zero);
    }
    player.play(); // not awaited: this Future only completes on pause
  }

  Future<void> pause() async {
    await player.pause();
    await save();
  }

  Future<void> togglePlay() => isPlaying ? pause() : play();

  /// Skip forward/back. Crosses into the previous/next file when needed.
  Future<void> seekBy(Duration offset) async {
    if (_book == null) return;
    final dur = player.duration ?? Duration.zero;
    final target = player.position + offset;

    if (target < Duration.zero) {
      if (isFirstFile) {
        await player.seek(Duration.zero);
      } else {
        final prevDur =
            await _loadFile(_fileIndex - 1, Duration.zero) ?? Duration.zero;
        final t = prevDur + target; // target is negative here
        await player.seek(t < Duration.zero ? Duration.zero : t);
      }
    } else if (dur > Duration.zero && target >= dur) {
      if (isLastFile) {
        final end = dur - const Duration(seconds: 1);
        await player.seek(end < Duration.zero ? Duration.zero : end);
      } else {
        await _loadFile(_fileIndex + 1, target - dur);
      }
    } else {
      await player.seek(target);
    }
    await save();
  }

  Future<void> seekTo(Duration position) async {
    if (_book == null) return;
    await player.seek(position);
    await save();
  }

  Future<void> previousFile() async {
    // Like music players: first press goes back to the start of the file.
    if (player.position > const Duration(seconds: 3) || isFirstFile) {
      await seekTo(Duration.zero);
    } else {
      await jumpToFile(_fileIndex - 1);
    }
  }

  Future<void> nextFile() async {
    if (!isLastFile) await jumpToFile(_fileIndex + 1);
  }

  Future<void> jumpToFile(int index) async {
    if (_book == null) return;
    await _loadFile(index, Duration.zero);
    await save();
  }

  Future<void> setSpeed(double value) async {
    final rounded = (value * 20).round() / 20; // steps of 0.05
    await player.setSpeed(rounded);
    _book?.speed = rounded;
    notifyListeners();
    await save();
  }

  // ---------------- Sleep timer ----------------

  static const _fadeDuration = Duration(seconds: 10);

  Timer? _sleepTicker;
  Duration? _sleepRemaining;
  bool _sleepAtEndOfFile = false;

  Duration? get sleepRemaining => _sleepRemaining;
  bool get sleepAtEndOfFile => _sleepAtEndOfFile;
  bool get sleepTimerActive => _sleepRemaining != null || _sleepAtEndOfFile;

  void startSleepTimer(Duration duration) {
    cancelSleepTimer();
    _sleepRemaining = duration;
    _sleepTicker =
        Timer.periodic(const Duration(seconds: 1), (_) => _tickSleep());
    notifyListeners();
  }

  void startSleepAtEndOfFile() {
    cancelSleepTimer();
    _sleepAtEndOfFile = true;
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTicker?.cancel();
    _sleepTicker = null;
    _sleepRemaining = null;
    _sleepAtEndOfFile = false;
    player.setVolume(1.0);
    notifyListeners();
  }

  void _tickSleep() {
    if (!isPlaying || _sleepRemaining == null) return; // only counts while playing

    final left = _sleepRemaining! - const Duration(seconds: 1);
    if (left <= Duration.zero) {
      _sleepTicker?.cancel();
      _sleepTicker = null;
      _sleepRemaining = null;
      pause().then((_) => player.setVolume(1.0));
      notifyListeners();
      return;
    }

    _sleepRemaining = left;
    // Fade out during the last 10 seconds.
    if (left < _fadeDuration) {
      player.setVolume(left.inMilliseconds / _fadeDuration.inMilliseconds);
    }
    notifyListeners();
  }

  // ---------------- Saving ----------------

  Future<void> save() async {
    final book = _book;
    if (book == null || _error != null) return;
    _lastSave = DateTime.now();
    book.currentFileIndex = _fileIndex;
    book.position = player.position;
    book.speed = player.speed;
    book.lastPlayed = DateTime.now();
    await ProgressStore.instance.save(book.toProgress());
  }
}
