class Bookmark {
  final int? id;
  final String bookId;
  final int fileIndex;
  final Duration position;
  final String note;
  final DateTime createdAt;

  const Bookmark({
    this.id,
    required this.bookId,
    required this.fileIndex,
    required this.position,
    this.note = '',
    required this.createdAt,
  });

  Bookmark copyWith({String? note}) => Bookmark(
        id: id,
        bookId: bookId,
        fileIndex: fileIndex,
        position: position,
        note: note ?? this.note,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'book_id': bookId,
        'file_index': fileIndex,
        'position_ms': position.inMilliseconds,
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Bookmark.fromMap(Map<String, Object?> m) => Bookmark(
        id: m['id'] as int,
        bookId: m['book_id'] as String,
        fileIndex: m['file_index'] as int,
        position: Duration(milliseconds: m['position_ms'] as int),
        note: (m['note'] as String?) ?? '',
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}
