import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/book.dart';
import 'read_along.dart' show SyncChapter, SyncParagraph;
import 'text_sync.dart';

/// Subtitles (.srt) shown as read-along text.
/// "Part 01.srt" next to "Part 01.mp3" belongs to that file.
class SrtSync implements TextSync {
  SrtSync._(this._cues, this.chapters, this._chapterOfFile);

  /// Per audio file: its subtitle lines in time order.
  final Map<int, List<_Cue>> _cues;

  @override
  final List<SyncChapter> chapters;

  final Map<int, int> _chapterOfFile;
  final _texts = <String>[];
  final _where = <({int file, Duration time})>[];

  /// Path of the .srt that belongs to an audio file (may not exist).
  static String srtPathFor(String audioPath) {
    final dot = audioPath.lastIndexOf('.');
    return '${dot > 0 ? audioPath.substring(0, dot) : audioPath}.srt';
  }

  static bool hasSubtitles(Book book) =>
      book.files.any((f) => File(srtPathFor(f)).existsSync());

  /// Reads every .srt of the book; null if there are none.
  static Future<SrtSync?> load(Book book) async {
    final cues = <int, List<_Cue>>{};
    for (var i = 0; i < book.files.length; i++) {
      final file = File(srtPathFor(book.files[i]));
      if (!await file.exists()) continue;
      final parsed = _parse(await file.readAsString());
      if (parsed.isNotEmpty) cues[i] = parsed;
    }
    if (cues.isEmpty) return null;

    // One chapter per audio file; lines grouped into paragraphs at pauses.
    final chapters = <SyncChapter>[];
    final chapterOfFile = <int, int>{};
    final sync = SrtSync._(cues, chapters, chapterOfFile);
    final files = cues.keys.toList()..sort();
    for (final f in files) {
      final paragraphs = <SyncParagraph>[];
      Duration? lastEnd;
      for (final cue in cues[f]!) {
        final index = sync._texts.length;
        sync._texts.add(cue.text);
        sync._where.add((file: f, time: cue.start));
        cue.sentence = index;
        final newParagraph = lastEnd == null ||
            cue.start - lastEnd > const Duration(milliseconds: 1500) ||
            paragraphs.last.sentences.length >= 6;
        if (newParagraph) {
          paragraphs.add(SyncParagraph([index], false));
        } else {
          paragraphs.last.sentences.add(index);
        }
        lastEnd = cue.end;
      }
      chapterOfFile[f] = chapters.length;
      chapters.add(SyncChapter(paragraphs));
    }
    return sync;
  }

  static final _time = RegExp(
      r'(\d+):(\d+):(\d+)[,.](\d+)\s*-->\s*(\d+):(\d+):(\d+)[,.](\d+)');

  static Duration _d(Match m, int i) => Duration(
        hours: int.parse(m.group(i)!),
        minutes: int.parse(m.group(i + 1)!),
        seconds: int.parse(m.group(i + 2)!),
        milliseconds: int.parse(m.group(i + 3)!.padRight(3, '0').substring(0, 3)),
      );

  static List<_Cue> _parse(String content) {
    final cues = <_Cue>[];
    final blocks = content.replaceAll('\r', '').split(RegExp(r'\n\s*\n'));
    for (final block in blocks) {
      final lines = block.trim().split('\n');
      final timeLine = lines.indexWhere((l) => _time.hasMatch(l));
      if (timeLine < 0) continue;
      final m = _time.firstMatch(lines[timeLine])!;
      final text = lines
          .skip(timeLine + 1)
          .join(' ')
          .replaceAll(RegExp(r'<[^>]+>|\{[^}]+\}'), '') // <i>, {\an8}...
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.isEmpty) continue;
      cues.add(_Cue(_d(m, 1), _d(m, 5), text));
    }
    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  // ---------------- TextSync ----------------

  @override
  late final List<int> sentenceChapter = [
    for (final w in _where) _chapterOfFile[w.file]!,
  ];

  @override
  String sentenceText(int sentence) => _texts[sentence];

  @override
  int sentenceAt(int file, Duration position) {
    final list = _cues[file];
    if (list == null) return -1;
    var lo = 0, hi = list.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid].start <= position) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (found < 0) return -1;
    final cue = list[found];
    // Keep the last line lit through short gaps.
    return position < cue.end + const Duration(seconds: 2) ? cue.sentence : -1;
  }

  @override
  ({int file, Duration time})? timeOfSentence(int sentence) => _where[sentence];

  @override
  int? chapterForFile(int file) => _chapterOfFile[file];

  @override
  Listenable? get changes => null;

  @override
  String? get status => null;
}

class _Cue {
  final Duration start;
  final Duration end;
  final String text;
  int sentence = 0;

  _Cue(this.start, this.end, this.text);
}
