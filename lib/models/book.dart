import '../services/read_along.dart';
import 'book_progress.dart';

enum BookStatus { newBook, started, finished }

class Book {
  /// The book's folder name, e.g. "5. Day of the Dragon".
  final String title;

  /// Full path of the book's folder. Used as the book's unique id.
  final String folderPath;

  /// Audio files in play order (naturally sorted).
  /// For read-along books this is empty until the EPUB's audio is extracted.
  List<String> files;

  /// Set for read-along books: an EPUB with synced narration.
  final String? epubPath;

  /// Text + timings, loaded when a read-along book is opened.
  ReadAlongData? readAlong;

  /// cover.jpg / folder.jpg / first image found, if any.
  final String? coverPath;

  // ---- Progress (saved in the database) ----
  int currentFileIndex;
  Duration position;
  bool finished;
  double speed; // each book remembers its own speed
  DateTime? lastPlayed;
  DateTime? finishedAt;

  Book({
    required this.title,
    required this.folderPath,
    required this.files,
    this.epubPath,
    this.coverPath,
    this.currentFileIndex = 0,
    this.position = Duration.zero,
    this.finished = false,
    this.speed = 1.0,
    this.lastPlayed,
    this.finishedAt,
  });

  /// Read-along books use the EPUB path, so their progress is separate
  /// from any plain audio files in the same folder.
  String get id => epubPath ?? folderPath;

  bool get isReadAlong => epubPath != null;
  bool get isReady => files.isNotEmpty;

  BookStatus get status {
    if (finished) return BookStatus.finished;
    if (currentFileIndex == 0 && position == Duration.zero) {
      return BookStatus.newBook;
    }
    return BookStatus.started;
  }

  /// Copies saved progress onto this book (after a library scan).
  void applyProgress(BookProgress? p) {
    if (p == null) return;
    // If files were removed since last time, don't point past the end.
    currentFileIndex =
        files.isEmpty ? p.fileIndex : p.fileIndex.clamp(0, files.length - 1);
    position = p.position;
    finished = p.finished;
    speed = p.speed;
    lastPlayed = p.lastPlayed;
    finishedAt = p.finishedAt;
  }

  BookProgress toProgress() => BookProgress(
        bookId: id,
        fileIndex: currentFileIndex,
        position: position,
        finished: finished,
        speed: speed,
        lastPlayed: lastPlayed,
        finishedAt: finishedAt,
      );
}
