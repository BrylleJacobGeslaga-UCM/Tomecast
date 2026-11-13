/// One row in the `progress` table: where you are in a book.
class BookProgress {
  final String bookId;
  final int fileIndex;
  final Duration position;
  final bool finished;
  final double speed;
  final DateTime? lastPlayed;

  const BookProgress({
    required this.bookId,
    required this.fileIndex,
    required this.position,
    required this.finished,
    required this.speed,
    this.lastPlayed,
  });

  Map<String, Object?> toMap() => {
        'book_id': bookId,
        'file_index': fileIndex,
        'position_ms': position.inMilliseconds,
        'finished': finished ? 1 : 0,
        'speed': speed,
        'last_played': lastPlayed?.millisecondsSinceEpoch,
      };

  factory BookProgress.fromMap(Map<String, Object?> m) => BookProgress(
        bookId: m['book_id'] as String,
        fileIndex: m['file_index'] as int,
        position: Duration(milliseconds: m['position_ms'] as int),
        finished: (m['finished'] as int) == 1,
        speed: (m['speed'] as num).toDouble(),
        lastPlayed: m['last_played'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['last_played'] as int),
      );
}
