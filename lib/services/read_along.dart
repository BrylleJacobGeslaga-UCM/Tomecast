import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

import 'epub_zip.dart';
import 'text_sync.dart';

// =====================================================================
// Data
// =====================================================================

/// One narrated piece of text (usually a sentence) and when it's spoken.
class SyncSentence {
  final int file; // index into ReadAlongData.audioFiles
  final Duration begin;
  final Duration end;
  final String text;

  const SyncSentence(this.file, this.begin, this.end, this.text);

  Map<String, Object> toJson() => {
        'f': file,
        'b': begin.inMilliseconds,
        'e': end.inMilliseconds,
        't': text,
      };

  factory SyncSentence.fromJson(Map<String, dynamic> j) => SyncSentence(
        j['f'] as int,
        Duration(milliseconds: j['b'] as int),
        Duration(milliseconds: j['e'] as int),
        j['t'] as String,
      );
}

/// A paragraph = sentences shown together. Headings are drawn bigger.
class SyncParagraph {
  final List<int> sentences; // indexes into ReadAlongData.sentences
  final bool heading;

  const SyncParagraph(this.sentences, this.heading);

  Map<String, Object> toJson() => {'s': sentences, 'h': heading};

  factory SyncParagraph.fromJson(Map<String, dynamic> j) => SyncParagraph(
        (j['s'] as List).cast<int>(),
        j['h'] as bool,
      );
}

/// One XHTML file of the book (usually a chapter).
class SyncChapter {
  final List<SyncParagraph> paragraphs;

  const SyncChapter(this.paragraphs);

  Map<String, Object> toJson() =>
      {'p': paragraphs.map((x) => x.toJson()).toList()};

  factory SyncChapter.fromJson(Map<String, dynamic> j) => SyncChapter([
        for (final x in j['p'] as List)
          SyncParagraph.fromJson(x as Map<String, dynamic>)
      ]);
}

class ReadAlongData implements TextSync {
  /// Audio files inside the EPUB, in play order (paths inside the ZIP).
  final List<String> audioEntries;
  final List<SyncSentence> sentences;
  @override
  final List<SyncChapter> chapters;

  /// Extracted audio files on the phone (same order as audioEntries).
  List<String> audioFiles = const [];

  /// sentenceChapter[i] = chapter that sentence i belongs to.
  @override
  late final List<int> sentenceChapter = _buildSentenceChapter();

  @override
  String sentenceText(int sentence) => sentences[sentence].text;

  @override
  ({int file, Duration time})? timeOfSentence(int sentence) =>
      (file: sentences[sentence].file, time: sentences[sentence].begin);

  @override
  int? chapterForFile(int file) {
    for (var i = 0; i < sentences.length; i++) {
      if (sentences[i].file == file) return sentenceChapter[i];
    }
    return null;
  }

  @override
  Listenable? get changes => null; // fully synced already

  @override
  String? get status => null;

  /// Per audio file: sentence indexes sorted by start time.
  late final List<List<int>> _byFile = _buildByFile();

  ReadAlongData({
    required this.audioEntries,
    required this.sentences,
    required this.chapters,
  });

  List<int> _buildSentenceChapter() {
    final result = List<int>.filled(sentences.length, 0);
    for (var c = 0; c < chapters.length; c++) {
      for (final para in chapters[c].paragraphs) {
        for (final s in para.sentences) {
          result[s] = c;
        }
      }
    }
    return result;
  }

  List<List<int>> _buildByFile() {
    final lists = List.generate(audioEntries.length, (_) => <int>[]);
    for (var i = 0; i < sentences.length; i++) {
      lists[sentences[i].file].add(i);
    }
    for (final l in lists) {
      l.sort((a, b) => sentences[a].begin.compareTo(sentences[b].begin));
    }
    return lists;
  }

  /// The sentence being spoken at [position] in audio file [file], or -1.
  @override
  int sentenceAt(int file, Duration position) {
    if (file < 0 || file >= _byFile.length) return -1;
    final list = _byFile[file];
    var lo = 0, hi = list.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (sentences[list[mid]].begin <= position) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (found == -1) return -1;
    final s = list[found];
    // Small gaps between sentences: keep the last one highlighted.
    return position < sentences[s].end + const Duration(seconds: 2) ? s : -1;
  }

  Map<String, Object> toJson() => {
        'version': 1,
        'audio': audioEntries,
        'sentences': sentences.map((s) => s.toJson()).toList(),
        'chapters': chapters.map((c) => c.toJson()).toList(),
      };

  factory ReadAlongData.fromJson(Map<String, dynamic> j) => ReadAlongData(
        audioEntries: (j['audio'] as List).cast<String>(),
        sentences: [
          for (final s in j['sentences'] as List)
            SyncSentence.fromJson(s as Map<String, dynamic>)
        ],
        chapters: [
          for (final c in j['chapters'] as List)
            SyncChapter.fromJson(c as Map<String, dynamic>)
        ],
      );
}

// =====================================================================
// Reading the EPUB
// =====================================================================

class ReadAlong {
  /// Quick check used by the library scanner: does this EPUB have
  /// synced narration (EPUB 3 Media Overlays)?
  static bool hasMediaOverlays(String epubPath) {
    try {
      final zip = EpubZip.open(epubPath);
      final opf = _opfPath(zip);
      if (opf == null) return false;
      return zip.readText(opf).contains('media-overlay');
    } catch (_) {
      return false;
    }
  }

  /// Gets the book ready to play: reads the text + timings (cached after
  /// the first time) and extracts the audio from the EPUB.
  /// [onProgress] gets messages like "Extracting audio 3 of 12".
  static Future<ReadAlongData> prepare(
    String epubPath, {
    void Function(String message)? onProgress,
  }) async {
    final cacheDir = await _cacheDirFor(epubPath);
    final jsonFile = File(p.join(cacheDir.path, 'sync.json'));

    // 1. Text + timings
    ReadAlongData data;
    if (await jsonFile.exists()) {
      onProgress?.call('Loading text…');
      data = ReadAlongData.fromJson(
          jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>);
    } else {
      onProgress?.call('Reading text and timings…');
      final json = await Isolate.run(() => _parse(epubPath).toJson());
      await jsonFile.writeAsString(jsonEncode(json));
      data = ReadAlongData.fromJson(json);
    }

    // 2. Audio: copy each file out of the EPUB once.
    final zip = EpubZip.open(epubPath);
    final files = <String>[];
    for (var i = 0; i < data.audioEntries.length; i++) {
      final entry = data.audioEntries[i];
      final out = File(p.join(cacheDir.path, 'audio',
          '${i.toString().padLeft(4, '0')}${p.extension(entry)}'));
      if (!await out.exists()) {
        onProgress?.call(
            'Extracting audio ${i + 1} of ${data.audioEntries.length}…');
        await zip.extractTo(entry, out.path);
      }
      files.add(out.path);
    }
    data.audioFiles = files;
    return data;
  }

  /// Deletes the extracted audio + cached text for this EPUB.
  static Future<void> clearCache(String epubPath) async {
    final dir = await _cacheDirFor(epubPath);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// One cache folder per EPUB. Changes if the EPUB file changes.
  static Future<Directory> _cacheDirFor(String epubPath) async {
    final stat = await File(epubPath).stat();
    final key = _fnv1a('$epubPath|${stat.size}|${stat.modified}');
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'read_along', key));
    await dir.create(recursive: true);
    return dir;
  }

  static String _fnv1a(String s) {
    var hash = 0xcbf29ce484222325;
    for (final c in utf8.encode(s)) {
      hash ^= c;
      hash = hash * 0x100000001b3; // wraps around at 64 bits
    }
    return hash.toUnsigned(64).toRadixString(16);
  }

  // ------------------------------------------------------------------

  static String? _opfPath(EpubZip zip) {
    if (!zip.contains('META-INF/container.xml')) return null;
    final container = zip.readText('META-INF/container.xml');
    final match = RegExp(r'full-path\s*=\s*"([^"]+)"').firstMatch(container);
    return match?.group(1);
  }

  /// Resolves [href] relative to the file [from], both paths inside the ZIP.
  static String _resolve(String from, String href) {
    final clean = Uri.decodeFull(href.split('#').first);
    return p.url.normalize(p.url.join(p.url.dirname(from), clean));
  }

  static const _blockTags = {
    'p', 'div', 'li', 'blockquote', 'pre', 'td', 'th', 'dd', 'dt',
    'figcaption', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'section',
  };

  /// Runs in a background isolate.
  static ReadAlongData _parse(String epubPath) {
    final zip = EpubZip.open(epubPath);
    final opfPath = _opfPath(zip);
    if (opfPath == null) throw const FormatException('Not a valid EPUB');

    final opf = XmlDocument.parse(zip.readText(opfPath));

    // Manifest: id → (href, media-overlay id)
    final hrefs = <String, String>{};
    final overlays = <String, String>{};
    for (final item in opf.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      hrefs[id] = _resolve(opfPath, href);
      final overlay = item.getAttribute('media-overlay');
      if (overlay != null) overlays[id] = overlay;
    }

    final audioEntries = <String>[];
    final audioIndex = <String, int>{};
    final sentences = <SyncSentence>[];
    final chapters = <SyncChapter>[];

    // Spine = reading order.
    for (final ref in opf.findAllElements('itemref')) {
      final idref = ref.getAttribute('idref');
      if (idref == null) continue;
      final overlayId = overlays[idref];
      final xhtmlPath = hrefs[idref];
      final smilPath = overlayId == null ? null : hrefs[overlayId];
      if (xhtmlPath == null || smilPath == null) continue;
      if (!zip.contains(smilPath) || !zip.contains(xhtmlPath)) continue;

      // ---- Chapter text: element id → element ----
      final xhtml = _parseXhtml(zip.readText(xhtmlPath));
      final byId = <String, XmlElement>{};
      for (final el in xhtml.descendants.whereType<XmlElement>()) {
        final id = el.getAttribute('id');
        if (id != null) byId[id] = el;
      }

      // ---- Timings: each <par> = one text fragment + one audio clip ----
      final smil = XmlDocument.parse(zip.readText(smilPath));
      final paragraphs = <SyncParagraph>[];
      final blockIds = Map<XmlElement, int>.identity();
      var currentBlock = -1;

      for (final par in smil.findAllElements('par')) {
        final texts = par.findElements('text');
        final audios = par.findElements('audio');
        final textEl = texts.isEmpty ? null : texts.first;
        final audioEl = audios.isEmpty ? null : audios.first;
        final textSrc = textEl?.getAttribute('src');
        final audioSrc = audioEl?.getAttribute('src');
        if (textSrc == null || audioSrc == null || !textSrc.contains('#')) {
          continue;
        }

        final fragment = Uri.decodeComponent(textSrc.split('#').last);
        final el = byId[fragment];
        if (el == null) continue;
        final text = el.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (text.isEmpty) continue;

        final audioPath = _resolve(smilPath, audioSrc);
        final file = audioIndex.putIfAbsent(audioPath, () {
          audioEntries.add(audioPath);
          return audioEntries.length - 1;
        });

        sentences.add(SyncSentence(
          file,
          _parseClock(audioEl!.getAttribute('clipBegin') ?? '0'),
          _parseClock(audioEl.getAttribute('clipEnd') ?? '0'),
          text,
        ));
        final sentenceIndex = sentences.length - 1;

        // Group sentences by the paragraph/heading they're in.
        final block = _blockOf(el);
        final blockId = blockIds.putIfAbsent(block, () => blockIds.length);
        if (blockId != currentBlock || paragraphs.isEmpty) {
          currentBlock = blockId;
          final tag = block.name.local.toLowerCase();
          final isHeading = tag.length == 2 && tag.startsWith('h') &&
              int.tryParse(tag.substring(1)) != null;
          paragraphs.add(SyncParagraph([sentenceIndex], isHeading));
        } else {
          paragraphs.last.sentences.add(sentenceIndex);
        }
      }

      if (paragraphs.isNotEmpty) chapters.add(SyncChapter(paragraphs));
    }

    if (sentences.isEmpty) {
      throw const FormatException('This EPUB has no synced narration');
    }
    return ReadAlongData(
      audioEntries: audioEntries,
      sentences: sentences,
      chapters: chapters,
    );
  }

  static XmlDocument _parseXhtml(String text) {
    try {
      // HTML entities like &nbsp; are common in EPUBs.
      return XmlDocument.parse(text,
          entityMapping: XmlDefaultEntityMapping.html5());
    } catch (_) {
      return XmlDocument.parse(text);
    }
  }

  static XmlElement _blockOf(XmlElement el) {
    XmlElement? cur = el;
    while (cur != null) {
      if (_blockTags.contains(cur.name.local.toLowerCase())) return cur;
      cur = cur.parentElement;
    }
    return el;
  }

  /// SMIL clock values: "0:01:02.500", "01:02.5", "62.5s", "500ms",
  /// "1.5min", "0.5h" or a plain number of seconds.
  static Duration _parseClock(String value) {
    final v = value.trim();
    double seconds;
    if (v.contains(':')) {
      final parts = v.split(':');
      seconds = double.parse(parts.last);
      seconds += int.parse(parts[parts.length - 2]) * 60;
      if (parts.length == 3) seconds += int.parse(parts[0]) * 3600;
    } else if (v.endsWith('ms')) {
      seconds = double.parse(v.substring(0, v.length - 2)) / 1000;
    } else if (v.endsWith('min')) {
      seconds = double.parse(v.substring(0, v.length - 3)) * 60;
    } else if (v.endsWith('h')) {
      seconds = double.parse(v.substring(0, v.length - 1)) * 3600;
    } else if (v.endsWith('s')) {
      seconds = double.parse(v.substring(0, v.length - 1));
    } else {
      seconds = double.tryParse(v) ?? 0;
    }
    return Duration(microseconds: (seconds * 1000000).round());
  }
}
