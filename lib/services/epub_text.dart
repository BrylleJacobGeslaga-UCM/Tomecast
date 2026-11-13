import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'epub_zip.dart';
import 'read_along.dart' show SyncChapter, SyncParagraph;

/// The text of a normal EPUB (no timings), split into chapters,
/// paragraphs, sentences and words. Used for live syncing.
class EpubText {
  final List<SyncChapter> chapters;
  final List<String> sentences;

  /// Index of each sentence's first word in [words].
  final List<int> sentenceWordStart;

  /// Every word of the book, normalized (lowercase, no punctuation).
  final List<String> words;

  const EpubText({
    required this.chapters,
    required this.sentences,
    required this.sentenceWordStart,
    required this.words,
  });

  /// Sentence containing word [word] (binary search).
  int sentenceOfWord(int word) {
    var lo = 0, hi = sentenceWordStart.length - 1, found = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (sentenceWordStart[mid] <= word) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  Map<String, Object> toJson() => {
        'version': 1,
        'chapters': chapters.map((c) => c.toJson()).toList(),
        'sentences': sentences,
        'wordStart': sentenceWordStart,
        'words': words,
      };

  factory EpubText.fromJson(Map<String, dynamic> j) => EpubText(
        chapters: [
          for (final c in j['chapters'] as List)
            SyncChapter.fromJson(c as Map<String, dynamic>)
        ],
        sentences: (j['sentences'] as List).cast<String>(),
        sentenceWordStart: (j['wordStart'] as List).cast<int>(),
        words: (j['words'] as List).cast<String>(),
      );

  // ------------------------------------------------------------------

  static const _blockTags = {
    'p', 'div', 'li', 'blockquote', 'pre', 'td', 'th', 'dd', 'dt',
    'figcaption', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  };

  /// Lowercase words without punctuation, used to match speech to text.
  static List<String> normalizeWords(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r"[’‘`]"), "'")
      .replaceAll(RegExp(r"[^a-z0-9' ]+"), ' ')
      .replaceAll("'", '')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();

  static final _sentenceSplit =
      RegExp('[^.!?…]+(?:[.!?…]+[\'"”’)\\]]*|\$)\\s*');

  /// Reads the EPUB. Slow for big books: run it in a background isolate.
  static EpubText parse(String epubPath) {
    final zip = EpubZip.open(epubPath);
    final container = zip.readText('META-INF/container.xml');
    final opfPath =
        RegExp(r'full-path\s*=\s*"([^"]+)"').firstMatch(container)?.group(1);
    if (opfPath == null) throw const FormatException('Not a valid EPUB');

    final opf = XmlDocument.parse(zip.readText(opfPath));
    final hrefs = <String, String>{};
    for (final item in opf.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id != null && href != null) {
        hrefs[id] = p.url.normalize(p.url.join(
            p.url.dirname(opfPath), Uri.decodeFull(href.split('#').first)));
      }
    }

    final chapters = <SyncChapter>[];
    final sentences = <String>[];
    final wordStart = <int>[];
    final words = <String>[];

    for (final ref in opf.findAllElements('itemref')) {
      final path = hrefs[ref.getAttribute('idref')];
      if (path == null || !zip.contains(path)) continue;

      XmlDocument doc;
      try {
        doc = XmlDocument.parse(zip.readText(path),
            entityMapping: XmlDefaultEntityMapping.html5());
      } catch (_) {
        continue; // skip broken pages
      }

      final paragraphs = <SyncParagraph>[];
      for (final el in doc.descendants.whereType<XmlElement>()) {
        final tag = el.name.local.toLowerCase();
        if (!_blockTags.contains(tag)) continue;
        // Only "leaf" blocks, so text isn't counted twice.
        final hasInnerBlock = el.descendants
            .whereType<XmlElement>()
            .any((d) => _blockTags.contains(d.name.local.toLowerCase()));
        if (hasInnerBlock) continue;

        final text = el.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (text.isEmpty) continue;

        final indexes = <int>[];
        for (final m in _sentenceSplit.allMatches(text)) {
          final sentence = m.group(0)!.trim();
          if (sentence.isEmpty) continue;
          sentences.add(sentence);
          wordStart.add(words.length);
          words.addAll(normalizeWords(sentence));
          indexes.add(sentences.length - 1);
        }
        if (indexes.isEmpty) continue;

        final isHeading = tag.length == 2 && tag.startsWith('h') &&
            int.tryParse(tag.substring(1)) != null;
        paragraphs.add(SyncParagraph(indexes, isHeading));
      }
      if (paragraphs.isNotEmpty) chapters.add(SyncChapter(paragraphs));
    }

    if (words.isEmpty) throw const FormatException('No text found in EPUB');
    return EpubText(
      chapters: chapters,
      sentences: sentences,
      sentenceWordStart: wordStart,
      words: words,
    );
  }
}
