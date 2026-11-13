import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/book.dart';
import '../models/bookmark.dart';
import 'app_settings.dart';
import 'chapter_reader.dart';
import 'file_info_service.dart';
import 'progress_store.dart';

/// App-wide player. Lives for the whole app (not just the player screen),
/// so audio keeps playing when you leave the screen or lock the phone.
///
/// The UI talks to this class. The lock screen / notification / headset
/// buttons reach it through TomecastAudioHandler.
class PlaybackService extends ChangeNotifier {
  PlaybackService._();
  static final instance = PlaybackService._();

  // Sound effects (volume boost + equalizer) run inside the player.
  final AndroidLoudnessEnhancer loudness = AndroidLoudnessEnhancer();
  final AndroidEqualizer equalizer = AndroidEqualizer();
  late final AudioPlayer player = AudioPlayer(
    audioPipeline: AudioPipeline(androidAudioEffects: [loudness, equalizer]),
  );

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
      await _flushListening(); // count time for the previous book
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

    _clearRepeat();
    _durations = List.filled(book.files.length, null);
    _titles = List.filled(book.files.length, null);
    _loadFileInfo(book);

    await player.setSpeed(book.speed);
    await _loadFile(_fileIndex, book.position);
    await applySoundSettings();
    updateFlipListener();
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
      if (playing) {
        _listenStart ??= DateTime.now();
      } else {
        _pausedAt ??= DateTime.now();
        _flushListening();
      }
    });

    // Auto-save every 5 seconds while playing, and write listening time
    // to the stats every minute (so a crash loses at most 1 minute).
    player.positionStream.listen((pos) {
      if (!player.playing) return;
      _checkRepeat(pos);
      _checkSkipEnd(pos);
      final now = DateTime.now();
      if (now.difference(_lastSave).inSeconds >= 5) save();
      final start = _listenStart;
      if (start != null && now.difference(start).inSeconds >= 60) {
        _flushListening();
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
    // "Skip intro": files started from the beginning start a bit later.
    final skipStart = AppSettings.instance.skipStart(book.id);
    if (position == Duration.zero && skipStart > Duration.zero) {
      position = skipStart;
    }
    try {
      final dur = await player.setFilePath(
        book.files[index],
        initialPosition: position,
      );
      if (dur != null && position >= dur) await player.seek(Duration.zero);
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
      _book!.finishedAt = DateTime.now();
      await player.pause();
      cancelSleepTimer();
      await save();
      notifyListeners();
      await _startNextBook();
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
      _book!.finishedAt = null;
      _pausedAt = null;
      await _loadFile(0, Duration.zero);
    }

    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (AppSettings.instance.smartRewind && pausedAt != null) {
      final back = _smartRewindAmount(DateTime.now().difference(pausedAt));
      if (back > Duration.zero) await seekBy(-back);
    }

    player.play(); // not awaited: this Future only completes on pause
  }

  Future<void> pause() async {
    await player.pause();
    await save();
  }

  /// Play/pause button (screen, notification). Clears "paused by flip".
  Future<void> togglePlay() {
    _pausedByFlip = false;
    return isPlaying ? pause() : play();
  }

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
    _clearRepeat();
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
    if (AppSettings.instance.sleepFadeOut && left < _fadeDuration) {
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
    if (!AppSettings.instance.shakeToExtend) return;
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

  // ---------------- Sound ----------------

  /// Applies boost / equalizer / pitch / skip silence from the settings.
  Future<void> applySoundSettings() async {
    final s = AppSettings.instance;
    try {
      await player.setPitch(s.pitch);
      await player.setSkipSilenceEnabled(s.skipSilence);
      await loudness.setEnabled(s.boostDb > 0);
      if (s.boostDb > 0) await loudness.setTargetGain(s.boostDb.toDouble());
      await equalizer.setEnabled(s.eqEnabled);
      if (s.eqEnabled) {
        final params = await equalizer.parameters;
        final gains = s.eqGains;
        for (var i = 0; i < params.bands.length && i < gains.length; i++) {
          await params.bands[i].setGain(
              gains[i].clamp(params.minDecibels, params.maxDecibels));
        }
      }
    } catch (e) {
      debugPrint('Sound settings not applied: $e');
    }
  }

  // ---------------- File lengths / titles ----------------

  List<Duration?> _durations = const [];
  List<String?> _titles = const [];

  Future<void> _loadFileInfo(Book book) async {
    final info = await FileInfoService.get(book.files);
    if (_book?.id != book.id) return;
    _durations = [for (final i in info) i?.duration];
    _titles = [for (final i in info) i?.title];
    notifyListeners();
  }

  /// Title tag of the current file, if it has one.
  String? get currentTitleTag =>
      _fileIndex < _titles.length ? _titles[_fileIndex] : null;

  String? titleTagOf(int file) => file < _titles.length ? _titles[file] : null;

  /// Total length of the book (null until all file lengths are known).
  Duration? get bookDuration {
    if (_durations.isEmpty || _durations.any((d) => d == null || d == Duration.zero)) {
      return null;
    }
    return _durations.fold<Duration>(Duration.zero, (a, b) => a + b!);
  }

  /// Position in the whole book (null until file lengths are known).
  Duration? get bookPosition {
    if (bookDuration == null) return null;
    var total = Duration.zero;
    for (var i = 0; i < _fileIndex; i++) {
      total += _durations[i]!;
    }
    return total + player.position;
  }

  // ---------------- A-B repeat ----------------

  Duration? _repeatA;
  Duration? _repeatB;
  int _repeatFile = 0;

  /// 0 = off, 1 = A set (waiting for B), 2 = repeating A→B.
  int get repeatState => _repeatB != null ? 2 : (_repeatA != null ? 1 : 0);
  Duration? get repeatA => _repeatA;
  Duration? get repeatB => _repeatB;

  /// Repeat button: 1st tap sets A, 2nd sets B and starts looping, 3rd stops.
  void cycleRepeat() {
    final pos = player.position;
    if (_repeatA == null) {
      _repeatA = pos;
      _repeatFile = _fileIndex;
    } else if (_repeatB == null) {
      if (_fileIndex != _repeatFile || pos <= _repeatA! + const Duration(seconds: 1)) {
        // B must come after A in the same file: start over with A here.
        _repeatA = pos;
        _repeatFile = _fileIndex;
      } else {
        _repeatB = pos;
        player.seek(_repeatA!);
      }
    } else {
      _clearRepeat();
    }
    notifyListeners();
  }

  void _clearRepeat() {
    _repeatA = null;
    _repeatB = null;
  }

  void _checkRepeat(Duration pos) {
    final a = _repeatA, b = _repeatB;
    if (a != null && b != null && _fileIndex == _repeatFile && pos >= b) {
      player.seek(a);
    }
  }

  // ---------------- Skip outro ----------------

  bool _skippingEnd = false;

  void _checkSkipEnd(Duration pos) {
    final book = _book;
    final dur = player.duration;
    if (book == null || dur == null || _skippingEnd || _changingFile) return;
    if (_repeatB != null) return; // don't fight A-B repeat
    final skipEnd = AppSettings.instance.skipEnd(book.id);
    if (skipEnd == Duration.zero || dur <= skipEnd * 2) return;
    if (pos >= dur - skipEnd) {
      _skippingEnd = true;
      _onFileCompleted().whenComplete(() => _skippingEnd = false);
    }
  }

  // ---------------- Flip to pause ----------------

  StreamSubscription<AccelerometerEvent>? _flipSub;
  DateTime? _faceDownSince;
  DateTime? _faceUpSince;
  bool _pausedByFlip = false;

  /// Starts/stops watching the phone's orientation (setting + book loaded).
  void updateFlipListener() {
    if (AppSettings.instance.flipToPause && _book != null) {
      _flipSub ??= accelerometerEventStream(
        samplingPeriod: SensorInterval.normalInterval,
      ).listen(_onTilt, onError: (_) {}, cancelOnError: true);
    } else {
      _flipSub?.cancel();
      _flipSub = null;
      _pausedByFlip = false;
    }
  }

  void _onTilt(AccelerometerEvent e) {
    const hold = Duration(milliseconds: 800);
    final now = DateTime.now();
    if (e.z < -8.5) {
      // Screen facing down
      _faceUpSince = null;
      _faceDownSince ??= now;
      if (isPlaying && now.difference(_faceDownSince!) > hold) {
        _pausedByFlip = true;
        pause();
      }
    } else if (e.z > 8.5) {
      // Screen facing up
      _faceDownSince = null;
      _faceUpSince ??= now;
      if (_pausedByFlip && !isPlaying && now.difference(_faceUpSince!) > hold) {
        _pausedByFlip = false;
        play();
      }
    } else {
      _faceDownSince = null;
      _faceUpSince = null;
    }
  }

  // ---------------- Next book ----------------

  /// The library's books in display order (set by the library screen).
  List<Book> library = const [];

  Future<void> _startNextBook() async {
    final current = _book;
    if (!AppSettings.instance.autoNextBook || current == null) return;
    final i = library.indexWhere((b) => b.id == current.id);
    if (i < 0) return;
    for (final next in library.skip(i + 1)) {
      if (next.status != BookStatus.finished && next.isReady) {
        await openBook(next);
        await play();
        return;
      }
    }
  }

  // ---------------- Listening stats ----------------

  DateTime? _listenStart;

  /// Writes the time listened since [_listenStart] to the stats table.
  Future<void> _flushListening() async {
    final start = _listenStart;
    final book = _book;
    final now = DateTime.now();
    _listenStart = player.playing ? now : null;
    if (start == null || book == null) return;

    final ms = now.difference(start).inMilliseconds;
    if (ms < 1000) return;
    await ProgressStore.instance.addListening(
      bookId: book.id,
      startedAt: start,
      listenedMs: ms,
      speed: player.speed,
    );
  }

  // ---------------- Library actions ----------------

  Future<void> setFinished(Book book, bool finished) async {
    final isCurrent = _book?.id == book.id;
    if (isCurrent && finished) await player.pause();
    book.finished = finished;
    book.finishedAt = finished ? DateTime.now() : null;
    await ProgressStore.instance.save(book.toProgress());
    notifyListeners();
  }

  /// Back to the start, as if never played. Bookmarks are kept.
  Future<void> resetProgress(Book book) async {
    final isCurrent = _book?.id == book.id;
    if (isCurrent) await player.pause();
    book
      ..currentFileIndex = 0
      ..position = Duration.zero
      ..finished = false
      ..finishedAt = null
      ..lastPlayed = null;
    await ProgressStore.instance.reset(book.id);
    if (isCurrent) {
      _pausedAt = null;
      await _loadFile(0, Duration.zero);
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
