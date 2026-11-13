import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_kit/download_model.dart';
import 'package:whisper_kit/whisper_kit.dart';

import '../models/book.dart';
import 'epub_text.dart';
import 'pcm_decoder.dart';
import 'playback_service.dart';
import 'read_along.dart' show SyncChapter;
import 'text_sync.dart';

/// A point where we know which word of the book is spoken at which time.
class Anchor {
  final int timeMs;
  final int word;
  const Anchor(this.timeMs, this.word);
}

/// Syncs your own EPUB to the audiobook on the phone, a little ahead of
/// where you're listening:
///
///  1. take the next 30 s of audio (Android decoder → 16 kHz WAV)
///  2. turn it into words with Whisper (offline)
///  3. find those words in the book → "anchors" (word X is spoken at time T)
///  4. highlight by interpolating between anchors
///
/// Results are saved, so each part of the book is only processed once.
class LiveSync extends ChangeNotifier implements TextSync {
  LiveSync._(this.book, this._dir, this.text);

  static const _chunk = Duration(seconds: 30);
  static const _lookahead = Duration(minutes: 3);
  static const _wordsPerSecond = 2.6; // typical narration speed
  static const _model = WhisperModel.base;

  final Book book;
  final Directory _dir;
  final EpubText text;

  /// Per audio file: anchors sorted by time.
  final Map<int, List<Anchor>> _anchors = {};

  /// Per audio file: 30-second chunks already processed.
  final Map<int, Set<int>> _done = {};

  Map<String, List<int>>? _trigramIndex;
  bool _running = false;
  String? _status;

  // ---------------- Setup ----------------

  /// Folder holding everything for one book: the EPUB copy, text, sync.
  static Future<Directory> folderFor(Book book) async {
    final base = await getApplicationSupportDirectory();
    final key = book.id.codeUnits.fold<int>(
        0x811c9dc5, (h, c) => ((h ^ c) * 0x01000193) & 0xffffffff);
    final dir = Directory(p.join(base.path, 'live_sync', key.toRadixString(16)));
    await dir.create(recursive: true);
    return dir;
  }

  static Future<bool> hasEbook(Book book) async =>
      File(p.join((await folderFor(book)).path, 'book.epub')).exists();

  /// Copies a picked EPUB in, replacing any earlier one + its sync data.
  static Future<void> attachEbook(Book book, String epubPath) async {
    final dir = await folderFor(book);
    await removeEbook(book);
    await dir.create(recursive: true);
    await File(epubPath).copy(p.join(dir.path, 'book.epub'));
  }

  static Future<void> removeEbook(Book book) async {
    final dir = await folderFor(book);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Loads the book's text (parsed once, then cached) and saved sync data.
  static Future<LiveSync> open(Book book) async {
    final dir = await folderFor(book);
    final epub = p.join(dir.path, 'book.epub');
    final textFile = File(p.join(dir.path, 'text.json'));

    EpubText text;
    if (await textFile.exists()) {
      text = EpubText.fromJson(
          jsonDecode(await textFile.readAsString()) as Map<String, dynamic>);
    } else {
      final json = await Isolate.run(() => EpubText.parse(epub).toJson());
      await textFile.writeAsString(jsonEncode(json));
      text = EpubText.fromJson(json);
    }

    final sync = LiveSync._(book, dir, text);
    await sync._loadSync();
    return sync;
  }

  // ---------------- TextSync (used by the read-along view) ----------------

  @override
  List<SyncChapter> get chapters => text.chapters;

  @override
  late final List<int> sentenceChapter = () {
    final result = List<int>.filled(text.sentences.length, 0);
    for (var c = 0; c < text.chapters.length; c++) {
      for (final para in text.chapters[c].paragraphs) {
        for (final s in para.sentences) {
          result[s] = c;
        }
      }
    }
    return result;
  }();

  @override
  String sentenceText(int sentence) => text.sentences[sentence];

  @override
  Listenable get changes => this;

  @override
  String? get status => _status;

  @override
  int sentenceAt(int file, Duration position) {
    final word = _wordAt(file, position.inMilliseconds);
    return word == null ? -1 : text.sentenceOfWord(word);
  }

  @override
  ({int file, Duration time})? timeOfSentence(int sentence) {
    final word = text.sentenceWordStart[sentence];
    for (final entry in _anchors.entries) {
      final list = entry.value;
      for (var i = 0; i + 1 < list.length; i++) {
        final a = list[i], b = list[i + 1];
        if (a.word <= word && word <= b.word && _closeEnough(a, b)) {
          final f = b.word == a.word ? 0.0 : (word - a.word) / (b.word - a.word);
          final ms = a.timeMs + ((b.timeMs - a.timeMs) * f).round();
          return (file: entry.key, time: Duration(milliseconds: ms));
        }
      }
    }
    return null;
  }

  @override
  int? chapterForFile(int file) {
    final list = _anchors[file];
    if (list == null || list.isEmpty) return null;
    return sentenceChapter[text.sentenceOfWord(list.first.word)];
  }

  /// Anchors far apart in time could hide a skipped/unsynced part.
  bool _closeEnough(Anchor a, Anchor b) => b.timeMs - a.timeMs <= 90000;

  /// Which book word is spoken at [ms] in [file] (interpolated), or null.
  int? _wordAt(int file, int ms) {
    final list = _anchors[file];
    if (list == null || list.isEmpty) return null;

    // Last anchor at or before ms
    var lo = 0, hi = list.length - 1, i = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid].timeMs <= ms) {
        i = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (i < 0) return null;
    final a = list[i];
    if (i + 1 < list.length && _closeEnough(a, list[i + 1])) {
      final b = list[i + 1];
      if (b.timeMs == a.timeMs) return a.word;
      final f = (ms - a.timeMs) / (b.timeMs - a.timeMs);
      return a.word + ((b.word - a.word) * f).round();
    }
    // After the last anchor: only guess a few seconds ahead.
    if (ms - a.timeMs <= 8000) {
      return a.word + ((ms - a.timeMs) / 1000 * _wordsPerSecond).round();
    }
    return null;
  }

  // ---------------- The worker ----------------

  Future<void>? _loopFuture;

  void start() {
    if (_running) return;
    _running = true;
    // If an old loop is still finishing a chunk, it simply carries on.
    _loopFuture ??= _loop().whenComplete(() => _loopFuture = null);
  }

  void stop() => _running = false;

  void _setStatus(String? s) {
    if (s == _status) return;
    _status = s;
    notifyListeners();
  }

  Future<void> _loop() async {
    try {
      if (!await _ensureModel()) {
        _running = false;
        return;
      }
      final whisper = Whisper(model: _model, modelDir: await _modelDir());
      final service = PlaybackService.instance;
      var failures = 0;

      while (_running) {
        if (service.book?.id != book.id || service.player.duration == null) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        final file = service.fileIndex;
        final pos = service.player.position;
        final duration = service.player.duration!;

        final first = pos.inMilliseconds ~/ _chunk.inMilliseconds;
        final last = math.min(
          (pos + _lookahead).inMilliseconds ~/ _chunk.inMilliseconds,
          (duration.inMilliseconds - 1) ~/ _chunk.inMilliseconds,
        );
        final done = _done.putIfAbsent(file, () => {});
        int? next;
        for (var k = first; k <= last; k++) {
          if (!done.contains(k)) {
            next = k;
            break;
          }
        }

        if (next == null) {
          _setStatus(null); // caught up
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }

        _setStatus(next == first ? 'Syncing this part…' : 'Syncing ahead…');
        try {
          await _processChunk(whisper, file, next);
          failures = 0;
        } catch (e) {
          debugPrint('Live sync chunk failed: $e');
          if (++failures >= 3) {
            // Probably a broken model download: delete it so it's
            // downloaded again next time.
            await Directory(await _modelDir()).delete(recursive: true);
            _setStatus('Syncing failed ($e). Close and reopen the text '
                'to try again.');
            _running = false;
            return;
          }
          continue; // retry this chunk
        }
        done.add(next);
        await _saveSync();
        notifyListeners();
      }
    } catch (e) {
      _running = false;
      _setStatus('Sync stopped: $e');
    }
  }

  Future<String> _modelDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'whisper'));
    await dir.create(recursive: true);
    return dir.path;
  }

  /// Downloads the speech model the first time (about 140 MB).
  Future<bool> _ensureModel() async {
    final dir = await _modelDir();
    final hasModel = Directory(dir)
        .listSync()
        .whereType<File>()
        .any((f) => f.path.contains('base') && f.lengthSync() > 50000000);
    if (hasModel) return true;

    try {
      await downloadModel(
        model: _model,
        destinationPath: dir,
        onDownloadProgress: (received, total) {
          if (total > 0) {
            _setStatus('Downloading speech model '
                '${(received * 100 / total).round()}% (one time only)');
          }
        },
      );
      return true;
    } catch (e) {
      _setStatus('Could not download the speech model. '
          'Check your internet and try again.');
      return false;
    }
  }

  Future<void> _processChunk(Whisper whisper, int file, int chunk) async {
    final start = _chunk * chunk;
    final wav = p.join(_dir.path, 'chunk.wav');

    // 1. Audio → WAV
    final length = await PcmDecoder.decodeToWav(
      audioPath: book.files[file],
      start: start,
      length: _chunk,
      wavPath: wav,
    );
    if (length < const Duration(seconds: 1)) return;

    // 2. WAV → text with timestamps
    final result = await whisper.transcribe(
      transcribeRequest: TranscribeRequest(
        audio: wav,
        language: 'en',
        threads: 4,
      ),
    );
    final segments = result.segments ?? [];

    // Words with times: spread each segment's time over its words.
    final words = <String>[];
    final times = <int>[];
    for (final seg in segments) {
      final segWords = EpubText.normalizeWords(seg.text);
      if (segWords.isEmpty) continue;
      final from = seg.fromTs.inMilliseconds;
      final span = math.max(0, seg.toTs.inMilliseconds - from);
      final totalChars =
          segWords.fold<int>(0, (n, w) => n + w.length + 1);
      var chars = 0;
      for (final w in segWords) {
        words.add(w);
        times.add(start.inMilliseconds + from + span * chars ~/ totalChars);
        chars += w.length + 1;
      }
    }
    if (words.length < 5) return; // music / silence

    // 3. Find those words in the book.
    final anchors = _align(words, times, file, start.inMilliseconds);
    if (anchors.isEmpty) return;
    _addAnchors(file, anchors);
  }

  // ---------------- Matching speech to the book ----------------

  Map<String, List<int>> get _index => _trigramIndex ??= () {
        final index = <String, List<int>>{};
        final w = text.words;
        for (var i = 0; i + 2 < w.length; i++) {
          index.putIfAbsent('${w[i]} ${w[i + 1]} ${w[i + 2]}', () => []).add(i);
        }
        return index;
      }();

  /// Where in the book we expect this chunk to be, from nearby anchors.
  ({int word, int radius})? _expected(int file, int startMs) {
    final here = _anchors[file] ?? const [];
    Anchor? before, after;
    for (final a in here) {
      if (a.timeMs <= startMs) {
        before = a;
      } else {
        after ??= a;
      }
    }
    if (before != null) {
      final dist = (startMs - before.timeMs) / 1000 * _wordsPerSecond;
      return (word: before.word + dist.round(), radius: 400 + (dist * 0.6).round());
    }
    if (after != null) {
      final dist = (after.timeMs - startMs) / 1000 * _wordsPerSecond;
      return (word: after.word - dist.round(), radius: 400 + (dist * 0.6).round());
    }
    // Previous file's last anchor: we're probably a bit after it.
    for (var f = file - 1; f >= 0; f--) {
      final prev = _anchors[f];
      if (prev != null && prev.isNotEmpty) {
        return (word: prev.last.word, radius: 6000);
      }
    }
    return null; // no idea yet: search the whole book
  }

  List<Anchor> _align(List<String> words, List<int> times, int file, int startMs) {
    final expected = _expected(file, startMs);
    final index = _index;

    // Each matching 3-word phrase "votes" for an offset (book pos - speech pos).
    final votes = <int, int>{};
    final hits = <int, List<int>>{}; // speech index → book positions
    for (var i = 0; i + 2 < words.length; i++) {
      final positions = index['${words[i]} ${words[i + 1]} ${words[i + 2]}'];
      if (positions == null) continue;
      final near = expected == null
          ? positions
          : positions
              .where((pos) => (pos - expected.word).abs() <= expected.radius)
              .toList();
      if (near.isEmpty || near.length > 30) continue; // too common
      hits[i] = near;
      for (final pos in near) {
        final bucket = (pos - i) ~/ 10;
        votes[bucket] = (votes[bucket] ?? 0) + 1;
      }
    }
    if (votes.isEmpty) return const [];

    // Best offset = bucket (plus neighbours) with most votes.
    var bestBucket = 0, bestScore = 0;
    for (final b in votes.keys) {
      final score = (votes[b - 1] ?? 0) + votes[b]! + (votes[b + 1] ?? 0);
      if (score > bestScore) {
        bestScore = score;
        bestBucket = b;
      }
    }
    if (bestScore < 4) return const []; // not confident: skip this chunk
    final offset = bestBucket * 10;

    // Anchors: speech words whose phrase matches near that offset,
    // kept in increasing book order.
    final anchors = <Anchor>[];
    var lastWord = -1;
    for (var i = 0; i + 2 < words.length; i++) {
      final positions = hits[i];
      if (positions == null) continue;
      int? best;
      for (final pos in positions) {
        if (((pos - i) - offset).abs() <= 25 &&
            (best == null || ((pos - i) - offset).abs() < ((best - i) - offset).abs())) {
          best = pos;
        }
      }
      if (best != null && best > lastWord) {
        anchors.add(Anchor(times[i], best));
        lastWord = best;
      }
    }
    return anchors;
  }

  void _addAnchors(int file, List<Anchor> fresh) {
    final list = _anchors.putIfAbsent(file, () => [])..addAll(fresh);
    list.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    // Drop anchors that go "backwards" in the book (bad matches).
    final clean = <Anchor>[];
    for (final a in list) {
      if (clean.isEmpty || a.word > clean.last.word) clean.add(a);
    }
    _anchors[file] = clean;
  }

  // ---------------- Saving ----------------

  File get _syncFile => File(p.join(_dir.path, 'sync.json'));

  Future<void> _loadSync() async {
    if (!await _syncFile.exists()) return;
    try {
      final j = jsonDecode(await _syncFile.readAsString()) as Map<String, dynamic>;
      final anchors = j['anchors'] as Map<String, dynamic>;
      anchors.forEach((file, list) {
        _anchors[int.parse(file)] = [
          for (final a in list as List)
            Anchor((a as List)[0] as int, a[1] as int)
        ];
      });
      final done = j['done'] as Map<String, dynamic>;
      done.forEach((file, list) {
        _done[int.parse(file)] = (list as List).cast<int>().toSet();
      });
    } catch (_) {
      // Corrupt file: start over.
      _anchors.clear();
      _done.clear();
    }
  }

  Future<void> _saveSync() async {
    final j = {
      'anchors': {
        for (final e in _anchors.entries)
          '${e.key}': [
            for (final a in e.value) [a.timeMs, a.word]
          ]
      },
      'done': {
        for (final e in _done.entries) '${e.key}': e.value.toList()
      },
    };
    await _syncFile.writeAsString(jsonEncode(j));
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
