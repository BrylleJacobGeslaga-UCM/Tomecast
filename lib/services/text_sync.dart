import 'package:flutter/foundation.dart';

import 'read_along.dart' show SyncChapter;

/// Anything that can show a book's text in sync with its audio:
///  * ReadAlongData – a ready-made Storyteller EPUB (fully synced)
///  * LiveSync      – your own EPUB, synced on the phone while you listen
abstract class TextSync {
  List<SyncChapter> get chapters;

  /// Chapter of each sentence.
  List<int> get sentenceChapter;

  String sentenceText(int sentence);

  /// Sentence being read at [position] of audio file [file], or -1 if
  /// that part isn't synced (yet).
  int sentenceAt(int file, Duration position);

  /// Where a sentence is spoken, or null if not synced (yet).
  ({int file, Duration time})? timeOfSentence(int sentence);

  /// Chapter to show for an audio file before playback reaches a sentence.
  int? chapterForFile(int file);

  /// Notifies when more of the book gets synced (null if it never changes).
  Listenable? get changes;

  /// Short status line like "Syncing…" (null = nothing to show).
  String? get status;
}
