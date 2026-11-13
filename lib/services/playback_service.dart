import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/book.dart';
import '../models/bookmark.dart';
import 'chapter_reader.dart';
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
    // Smart rewind also applies when you come back to a book later.
    _pausedAt = book.lastPlayed;
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

    // Remember when playback stopped (pause button, phone call, unplugged
    // headphones, sleep timer...) for smart rewind.
    player.playingStream.listen((playing) {
      if (!playing) _pausedAt ??= DateTime.now();
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
    _chapters = const [];
    try {
      final dur = await player.setFilePath(
        book.files[index],
        initialPosition: position,
      );
      _error = null;
      _loadChapters(book.files[index]);
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

  // ---------------- Chapters (inside .m4b files) ----------------

  List<Chapter> _chapters = const [];

  /// Chapters of the current file. Empty if the file has none.
  List<Chapter> get chapters => _chapters;
  bool get hasChapters => _chapters.length > 1;

  Future<void> _loadChapters(String path) async {
    final result = await ChapterReader.read(path);
    if (_book == null || currentFilePath != path) return; // file changed
    _chapters = result;
    notifyListeners();
  }

  /// Index of the chapter at [position], or -1 without chapters.
  int chapterIndexAt(Duration position) {
    if (!hasChapters) return -1;
    var index = 0;
    for (var i = 0; i < _chapters.length; i++) {
      if (_chapters[i].start <= position) index = i;
    }
    return index;
  }

  // ---------------- Controls ----------------

  // Smart rewind: go back a little after a pause so you don't lose
  // the sentence you were in. Longer pause → bigger rewind.
  DateTime? _pausedAt;
  bool smartRewindEnabled = true;

  Duration _smartRewindAmount(Duration paused) {
    if (paused < const Duration(seconds: 5)) return Duration.zero;
    if (paused < const Duration(minutes: 1)) return const Duration(seconds: 2);
    if (paused < const Duration(minutes: 10)) return const Duration(seconds: 5);
    if (paused < const Duration(hours: 1)) return const Duration(seconds: 10);
    return const Duration(seconds: 20);
  }

  Future<void> play() async {
    if (_book == null) return;
    // Book finished and you press play again → start over.
    if (player.processingState == ProcessingState.completed) {
      _book!.finished = false;
      _pausedAt = null;
      await _loadFile(0, Duration.zero);
    }

    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (smartRewindEnabled && pausedAt != null) {
      final back = _smartRewindAmount(DateTime.now().difference(pausedAt));
      if (back > Duration.zero) await seekBy(-back);
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
    _pausedAt = null; // you picked a spot yourself: don't rewind from it
    await player.seek(position);
    await save();
  }

  /// Go to a file + position (used by bookmarks).
  Future<void> jumpTo(int fileIndex, Duration position) async {
    if (_book == null) return;
    _pausedAt = null;
    if (fileIndex == _fileIndex) {
      await player.seek(position);
    } else {
      await _loadFile(fileIndex, position);
    }
    await save();
  }

  /// "Previous" button: previous chapter if the file has chapters,
  /// otherwise previous file. First press goes back to the start.
  Future<void> previous() async {
    final pos = player.position;
    if (hasChapters) {
      final i = chapterIndexAt(pos);
      final chapterStart = _chapters[i].start;
      if (pos - chapterStart > const Duration(seconds: 3)) {
        return seekTo(chapterStart);
      }
      if (i > 0) return seekTo(_chapters[i - 1].start);
      // At the start of the first chapter → previous file (below).
    }
    if (pos > const Duration(seconds: 3) || isFirstFile) {
      await seekTo(Duration.zero);
    } else {
      await jumpToFile(_fileIndex - 1);
    }
  }

  /// "Next" button: next chapter if the file has chapters, otherwise next file.
  Future<void> next() async {
    if (hasChapters) {
      final i = chapterIndexAt(player.position);
      if (i < _chapters.length - 1) return seekTo(_chapters[i + 1].start);
    }
    if (!isLastFile) await jumpToFile(_fileIndex + 1);
  }

  Future<void> jumpToFile(int index) async {
    if (_book == null) return;
    _pausedAt = null;
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

  // ---------------- Bookmarks ----------------

  Future<List<Bookmark>> getBookmarks() async {
    if (_book == null) return [];
    return ProgressStore.instance.getBookmarks(_book!.id);
  }

  Future<void> addBookmark(String note) async {
    if (_book == null) return;
    await ProgressStore.instance.addBookmark(Bookmark(
      bookId: _book!.id,
      fileIndex: _fileIndex,
      position: player.position,
      note: note.trim(),
      createdAt: DateTime.now(),
    ));
  }

  // ---------------- Sleep timer ----------------

  static const _fadeDuration = Duration(seconds: 10);
  static const _shakeGraceTime = Duration(minutes: 1);

  Timer? _sleepTicker;
  Duration? _sleepRemaining;
  Duration? _sleepChosen; // what the user picked, for shake-to-reset
  bool _sleepAtEndOfFile = false;
  DateTime? _sleepExpiredAt;
  Timer? _shakeGraceTimer;
  StreamSubscription? _shakeSub;
  DateTime _lastShake = DateTime.fromMillisecondsSinceEpoch(0);

  Duration? get sleepRemaining => _sleepRemaining;
  bool get sleepAtEndOfFile => _sleepAtEndOfFile;
  bool get sleepTimerActive => _sleepRemaining != null || _sleepAtEndOfFile;

  void startSleepTimer(Duration duration) {
    cancelSleepTimer();
    _sleepChosen = duration;
    _sleepRemaining = duration;
    _sleepTicker =
        Timer.periodic(const Duration(seconds: 1), (_) => _tickSleep());
    _startShakeListener();
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
    _sleepChosen = null;
    _sleepAtEndOfFile = false;
    _sleepExpiredAt = null;
    _shakeGraceTimer?.cancel();
    _stopShakeListener();
    player.setVolume(1.0);
    notifyListeners();
  }

  void _tickSleep() {
    if (!isPlaying || _sleepRemaining == null) return; // only counts while playing

    final left = _sleepRemaining! - const Duration(seconds: 1);
    if (left <= Duration.zero) {
      _onSleepTimerExpired();
      return;
    }

    _sleepRemaining = left;
    // Fade out during the last 10 seconds.
    if (left < _fadeDuration) {
      player.setVolume(left.inMilliseconds / _fadeDuration.inMilliseconds);
    }
    notifyListeners();
  }

  void _onSleepTimerExpired() {
    _sleepTicker?.cancel();
    _sleepTicker = null;
    _sleepRemaining = null;
    _sleepExpiredAt = DateTime.now();
    pause().then((_) => player.setVolume(1.0));

    // You can still shake for 1 minute after it stops to keep listening.
    _shakeGraceTimer?.cancel();
    _shakeGraceTimer = Timer(_shakeGraceTime, () {
      _sleepExpiredAt = null;
      _sleepChosen = null;
      _stopShakeListener();
    });
    notifyListeners();
  }

  // ---- Shake to reset the sleep timer ----

  void _startShakeListener() {
    _shakeSub ??= userAccelerometerEventStream().listen((e) {
      // userAccelerometer excludes gravity; ~12 m/s² is a deliberate shake.
      final force = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      if (force < 12) return;
      final now = DateTime.now();
      if (now.difference(_lastShake) < const Duration(seconds: 2)) return;
      _lastShake = now;
      _onShake();
    }, onError: (_) {
      // Phone has no accelerometer: shake just won't work.
    }, cancelOnError: true);
  }

  void _stopShakeListener() {
    _shakeSub?.cancel();
    _shakeSub = null;
  }

  void _onShake() {
    final chosen = _sleepChosen;
    if (chosen == null) return;

    if (_sleepRemaining != null) {
      // Timer running → reset it to the full time.
      _sleepRemaining = chosen;
      player.setVolume(1.0);
      HapticFeedback.mediumImpact();
      notifyListeners();
    } else if (_sleepExpiredAt != null &&
        DateTime.now().difference(_sleepExpiredAt!) < _shakeGraceTime) {
      // Timer just stopped playback → restart timer and keep listening.
      HapticFeedback.mediumImpact();
      startSleepTimer(chosen);
      play();
    }
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
