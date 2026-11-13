import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/book.dart';
import 'progress_store.dart';

/// Plays one book: loads its files one at a time, moves to the next file
/// when one ends, and saves your position every few seconds.
///
/// In Step 3 this moves into a background audio service so playback
/// continues when you leave the screen or lock the phone.
class PlayerController extends ChangeNotifier {
  PlayerController(this.book)
      : _fileIndex = book.currentFileIndex.clamp(0, book.files.length - 1);

  final Book book;
  final AudioPlayer player = AudioPlayer();

  int _fileIndex;
  bool _ready = false;
  bool _changingFile = false;
  String? _error;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  final _subs = <StreamSubscription>[];

  int get fileIndex => _fileIndex;
  bool get ready => _ready;
  String? get error => _error;
  double get speed => player.speed;
  bool get isFirstFile => _fileIndex == 0;
  bool get isLastFile => _fileIndex == book.files.length - 1;
  String get currentFilePath => book.files[_fileIndex];

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

  Future<void> init() async {
    await player.setSpeed(book.speed);
    await _loadFile(_fileIndex, book.position);

    _subs.add(player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _onFileCompleted();
      }
      notifyListeners();
    }));

    // Auto-save every 5 seconds while playing.
    _subs.add(player.positionStream.listen((_) {
      if (player.playing &&
          DateTime.now().difference(_lastSave).inSeconds >= 5) {
        save();
      }
    }));

    _ready = true;
    notifyListeners();
  }

  /// Loads file [index] and starts at [position]. Returns the file's length.
  /// If the player was playing, it keeps playing the new file.
  Future<Duration?> _loadFile(int index, Duration position) async {
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
    if (_changingFile) return; // ignore duplicate "completed" events

    if (isLastFile) {
      book.finished = true;
      await player.pause();
      await save();
      notifyListeners();
      return;
    }
    await _loadFile(_fileIndex + 1, Duration.zero);
    player.play();
    await save();
  }

  // ---------------- Controls ----------------

  Future<void> togglePlay() async {
    if (isPlaying) {
      await player.pause();
      await save();
      return;
    }
    // Book finished and you press play again → start over.
    if (player.processingState == ProcessingState.completed) {
      book.finished = false;
      await _loadFile(0, Duration.zero);
    }
    player.play(); // not awaited: this Future only completes on pause
  }

  /// Skip forward/back. Crosses into the previous/next file when needed.
  Future<void> seekBy(Duration offset) async {
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
    await _loadFile(index, Duration.zero);
    await save();
  }

  Future<void> setSpeed(double value) async {
    final rounded = (value * 20).round() / 20; // steps of 0.05
    await player.setSpeed(rounded);
    book.speed = rounded;
    notifyListeners();
    await save();
  }

  // ---------------- Saving ----------------

  Future<void> save() async {
    _lastSave = DateTime.now();
    book.currentFileIndex = _fileIndex;
    book.position = player.position;
    book.speed = player.speed;
    book.lastPlayed = DateTime.now();
    await ProgressStore.instance.save(book.toProgress());
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    // save() reads the position right away, before the player is disposed.
    if (_ready && _error == null) save();
    player.dispose();
    super.dispose();
  }
}
