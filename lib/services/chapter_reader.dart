import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

class Chapter {
  final String title;
  final Duration start;

  const Chapter(this.title, this.start);
}

/// Reads chapter markers stored inside .m4b / .m4a / .mp4 files.
///
/// Supports both common formats:
///  * Nero chapters ("chpl" box), used by many converters
///  * QuickTime chapter tracks (a hidden text track), used by Audible/Apple
///
/// Runs in a background isolate so big files don't freeze the UI.
class ChapterReader {
  static final _cache = <String, List<Chapter>>{};

  static Future<List<Chapter>> read(String path) async {
    final cached = _cache[path];
    if (cached != null) return cached;

    // 1. A .cue sheet next to the file wins (works for any audio format).
    final cue = _readCue(path);
    if (cue.length > 1) {
      _cache[path] = cue;
      return cue;
    }

    final lower = path.toLowerCase();
    final isMp4 = lower.endsWith('.m4b') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.mp4');

    // 2. Chapters stored inside .m4b / .m4a files.
    List<Chapter> result = const [];
    if (isMp4) {
      try {
        result = await Isolate.run(() => _readSync(path));
      } catch (_) {
        result = const []; // unreadable / unusual file: just no chapters
      }
    }
    _cache[path] = result;
    return result;
  }

  // ---------------- .cue sheets ----------------

  /// Reads chapters from a .cue file in the same folder:
  ///   "Book.cue" next to "Book.mp3", or any .cue whose FILE line names
  ///   this audio file.
  ///
  ///   FILE "Book.mp3" MP3
  ///     TRACK 01 AUDIO
  ///       TITLE "Chapter 1"
  ///       INDEX 01 00:00:00     (minutes:seconds:frames, 75 frames/second)
  static List<Chapter> _readCue(String audioPath) {
    try {
      final dir = File(audioPath).parent;
      final name = audioPath.split(Platform.pathSeparator).last;
      final base = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;

      final cues = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.cue'))
          .toList();
      if (cues.isEmpty) return const [];

      // Prefer "same name.cue", then any cue mentioning this file.
      cues.sort((a, b) {
        final aSame = a.path.endsWith('$base.cue') ? 0 : 1;
        final bSame = b.path.endsWith('$base.cue') ? 0 : 1;
        return aSame - bSame;
      });

      for (final cueFile in cues) {
        final lines = cueFile.readAsLinesSync();
        final chapters = <Chapter>[];
        // "Book.cue" next to "Book.m4b" counts even if its FILE line names
        // the original (e.g. Book.wav) it was made for.
        final sameName = cueFile.path.endsWith('$base.cue');
        var inThisFile = sameName;
        String? title;
        for (final raw in lines) {
          final line = raw.trim();
          final upper = line.toUpperCase();
          if (upper.startsWith('FILE ')) {
            final fileName = RegExp(r'"([^"]+)"').firstMatch(line)?.group(1);
            inThisFile = sameName ||
                fileName == null ||
                fileName.toLowerCase() == name.toLowerCase();
            title = null;
          } else if (!inThisFile) {
            continue;
          } else if (upper.startsWith('TRACK ')) {
            title = null;
          } else if (upper.startsWith('TITLE ')) {
            title = RegExp(r'"([^"]*)"').firstMatch(line)?.group(1) ??
                line.substring(6).trim();
          } else if (upper.startsWith('INDEX 01 ')) {
            final m = RegExp(r'(\d+):(\d+):(\d+)').firstMatch(line);
            if (m == null) continue;
            final ms = int.parse(m.group(1)!) * 60000 +
                int.parse(m.group(2)!) * 1000 +
                int.parse(m.group(3)!) * 1000 ~/ 75;
            chapters.add(Chapter(
              (title == null || title.isEmpty)
                  ? 'Chapter ${chapters.length + 1}'
                  : title,
              Duration(milliseconds: ms),
            ));
          }
        }
        if (chapters.length > 1) return chapters;
      }
    } catch (_) {
      // Unreadable cue: ignore.
    }
    return const [];
  }

  // ---------------------------------------------------------------------

  static List<Chapter> _readSync(String path) {
    final raf = File(path).openSync();
    try {
      final moov = _readTopLevelBox(raf, 'moov');
      if (moov == null) return const [];

      final nero = _readNero(moov);
      if (nero.length > 1) return nero;

      return _readQuickTime(raf, moov);
    } finally {
      raf.closeSync();
    }
  }

  /// Walks the top-level boxes of the file (skipping the huge audio data)
  /// and returns the payload of the first box of [type].
  static Uint8List? _readTopLevelBox(RandomAccessFile raf, String type) {
    final length = raf.lengthSync();
    var pos = 0;
    while (pos + 8 <= length) {
      raf.setPositionSync(pos);
      final h = raf.readSync(16);
      if (h.length < 8) return null;
      final bd = ByteData.sublistView(h);

      var size = bd.getUint32(0);
      final boxType = String.fromCharCodes(h, 4, 8);
      var header = 8;
      if (size == 1) {
        if (h.length < 16) return null;
        size = bd.getUint64(8);
        header = 16;
      } else if (size == 0) {
        size = length - pos;
      }
      if (size < header) return null;

      if (boxType == type) {
        if (size > 128 * 1024 * 1024) return null; // sanity limit
        raf.setPositionSync(pos + header);
        return raf.readSync(size - header);
      }
      pos += size;
    }
    return null;
  }

  /// Child boxes inside data[start..end).
  static Iterable<_Box> _children(Uint8List data, int start, int end) sync* {
    final bd = ByteData.sublistView(data);
    var pos = start;
    while (pos + 8 <= end) {
      var size = bd.getUint32(pos);
      final type = String.fromCharCodes(data, pos + 4, pos + 8);
      var header = 8;
      if (size == 1) {
        if (pos + 16 > end) return;
        size = bd.getUint64(pos + 8);
        header = 16;
      } else if (size == 0) {
        size = end - pos;
      }
      if (size < header || pos + size > end) return;
      yield _Box(type, pos + header, pos + size);
      pos += size;
    }
  }

  static _Box? _child(Uint8List data, _Box? parent, String type) {
    if (parent == null) return null;
    for (final b in _children(data, parent.start, parent.end)) {
      if (b.type == type) return b;
    }
    return null;
  }

  // ---------------- Nero chapters: moov/udta/chpl ----------------

  static List<Chapter> _readNero(Uint8List moov) {
    final root = _Box('moov', 0, moov.length);
    final chpl = _child(moov, _child(moov, root, 'udta'), 'chpl');
    if (chpl == null) return const [];

    final bd = ByteData.sublistView(moov);
    var p = chpl.start;
    final version = moov[p];
    p += 4; // version + flags
    if (version != 0) p += 4;
    if (p >= chpl.end) return const [];

    final count = moov[p];
    p += 1;

    final chapters = <Chapter>[];
    for (var i = 0; i < count && p + 9 <= chpl.end; i++) {
      final start100ns = bd.getUint64(p);
      p += 8;
      final len = moov[p];
      p += 1;
      if (p + len > chpl.end) break;
      final title = utf8.decode(moov.sublist(p, p + len), allowMalformed: true);
      p += len;
      chapters.add(Chapter(
        _cleanTitle(title, i),
        Duration(microseconds: start100ns ~/ 10),
      ));
    }
    return chapters;
  }

  // ---------------- QuickTime chapter track ----------------

  static List<Chapter> _readQuickTime(RandomAccessFile raf, Uint8List moov) {
    final bd = ByteData.sublistView(moov);
    final traks = _children(moov, 0, moov.length)
        .where((b) => b.type == 'trak')
        .toList();

    // 1. Which track IDs are chapter tracks? (listed in tref/chap)
    final chapterIds = <int>{};
    for (final trak in traks) {
      final chap = _child(moov, _child(moov, trak, 'tref'), 'chap');
      if (chap == null) continue;
      for (var p = chap.start; p + 4 <= chap.end; p += 4) {
        chapterIds.add(bd.getUint32(p));
      }
    }
    if (chapterIds.isEmpty) return const [];

    // 2. Read that track's samples: each sample = one chapter title.
    for (final trak in traks) {
      final tkhd = _child(moov, trak, 'tkhd');
      if (tkhd == null) continue;
      final tkhdVersion = moov[tkhd.start];
      final trackId =
          bd.getUint32(tkhd.start + 4 + (tkhdVersion == 1 ? 16 : 8));
      if (!chapterIds.contains(trackId)) continue;

      final mdia = _child(moov, trak, 'mdia');
      final mdhd = _child(moov, mdia, 'mdhd');
      final stbl = _child(moov, _child(moov, mdia, 'minf'), 'stbl');
      if (mdhd == null || stbl == null) continue;

      final mdhdVersion = moov[mdhd.start];
      final timescale =
          bd.getUint32(mdhd.start + 4 + (mdhdVersion == 1 ? 16 : 8));
      if (timescale == 0) continue;

      final stts = _child(moov, stbl, 'stts');
      final stsz = _child(moov, stbl, 'stsz');
      final stsc = _child(moov, stbl, 'stsc');
      final stco = _child(moov, stbl, 'stco');
      final co64 = _child(moov, stbl, 'co64');
      if (stts == null || stsz == null || stsc == null) continue;
      if (stco == null && co64 == null) continue;

      // Start time of each sample
      final times = <int>[];
      var t = 0;
      final sttsCount = bd.getUint32(stts.start + 4);
      for (var i = 0; i < sttsCount && times.length < 10000; i++) {
        final count = bd.getUint32(stts.start + 8 + i * 8);
        final delta = bd.getUint32(stts.start + 12 + i * 8);
        for (var j = 0; j < count && times.length < 10000; j++) {
          times.add(t);
          t += delta;
        }
      }

      // Size of each sample
      final fixedSize = bd.getUint32(stsz.start + 4);
      final sampleCount = math.min(bd.getUint32(stsz.start + 8), 10000);
      int sizeOf(int i) =>
          fixedSize != 0 ? fixedSize : bd.getUint32(stsz.start + 12 + i * 4);

      // Where each chunk starts in the file
      final offsets = <int>[];
      if (stco != null) {
        final n = bd.getUint32(stco.start + 4);
        for (var i = 0; i < n; i++) {
          offsets.add(bd.getUint32(stco.start + 8 + i * 4));
        }
      } else {
        final n = bd.getUint32(co64!.start + 4);
        for (var i = 0; i < n; i++) {
          offsets.add(bd.getUint64(co64.start + 8 + i * 8));
        }
      }

      // Samples per chunk (stored as runs)
      final stscCount = bd.getUint32(stsc.start + 4);
      final runs = <List<int>>[
        for (var i = 0; i < stscCount; i++)
          [
            bd.getUint32(stsc.start + 8 + i * 12), // first chunk (1-based)
            bd.getUint32(stsc.start + 12 + i * 12), // samples per chunk
          ]
      ];

      // File position of each sample
      final sampleOffsets = <int>[];
      var sample = 0;
      for (var c = 0; c < offsets.length && sample < sampleCount; c++) {
        var perChunk = 1;
        for (final run in runs) {
          if (run[0] <= c + 1) {
            perChunk = run[1];
          } else {
            break;
          }
        }
        var off = offsets[c];
        for (var k = 0; k < perChunk && sample < sampleCount; k++) {
          sampleOffsets.add(off);
          off += sizeOf(sample);
          sample++;
        }
      }

      // Read the text of each sample: 2-byte length + text
      final chapters = <Chapter>[];
      final n = math.min(sampleOffsets.length, times.length);
      for (var i = 0; i < n; i++) {
        final size = sizeOf(i);
        if (size < 2) continue;
        raf.setPositionSync(sampleOffsets[i]);
        final bytes = raf.readSync(math.min(size, 1024));
        if (bytes.length < 2) continue;
        final len = (bytes[0] << 8) | bytes[1];
        final text = _decodeText(
            bytes.sublist(2, math.min(2 + len, bytes.length)));
        chapters.add(Chapter(
          _cleanTitle(text, i),
          Duration(microseconds: times[i] * 1000000 ~/ timescale),
        ));
      }
      if (chapters.length > 1) return chapters;
    }
    return const [];
  }

  static String _decodeText(Uint8List bytes) {
    // UTF-16 with byte-order mark
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final codes = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        codes.add((bytes[i] << 8) | bytes[i + 1]);
      }
      return String.fromCharCodes(codes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _cleanTitle(String title, int index) {
    final t = title.replaceAll('\u0000', '').trim();
    return t.isEmpty ? 'Chapter ${index + 1}' : t;
  }
}

class _Box {
  final String type;
  final int start; // payload start
  final int end; // box end

  const _Box(this.type, this.start, this.end);
}
