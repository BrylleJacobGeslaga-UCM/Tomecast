import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/book_progress.dart';
import '../models/bookmark.dart';

/// Local SQLite database: progress per book + bookmarks.
/// Listening stats will get their own table in a later step.
class ProgressStore {
  ProgressStore._();
  static final instance = ProgressStore._();

  Database? _db;

  Future<Database> get _database async {
    return _db ??= await openDatabase(
      p.join(await getDatabasesPath(), 'audiobooks.db'),
      version: 2,
      onCreate: (db, version) async {
        await _createProgressTable(db);
        await _createBookmarksTable(db);
      },
      // Existing installs (from Step 2/3) only have the progress table.
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createBookmarksTable(db);
      },
    );
  }

  static Future<void> _createProgressTable(Database db) => db.execute('''
        CREATE TABLE progress (
          book_id     TEXT PRIMARY KEY,
          file_index  INTEGER NOT NULL DEFAULT 0,
          position_ms INTEGER NOT NULL DEFAULT 0,
          finished    INTEGER NOT NULL DEFAULT 0,
          speed       REAL    NOT NULL DEFAULT 1.0,
          last_played INTEGER
        )
      ''');

  static Future<void> _createBookmarksTable(Database db) async {
    await db.execute('''
      CREATE TABLE bookmarks (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id     TEXT    NOT NULL,
        file_index  INTEGER NOT NULL,
        position_ms INTEGER NOT NULL,
        note        TEXT    NOT NULL DEFAULT '',
        created_at  INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_bookmarks_book ON bookmarks(book_id)');
  }

  // ---------------- Progress ----------------

  Future<Map<String, BookProgress>> getAll() async {
    final db = await _database;
    final rows = await db.query('progress');
    return {
      for (final row in rows)
        row['book_id'] as String: BookProgress.fromMap(row),
    };
  }

  Future<void> save(BookProgress progress) async {
    final db = await _database;
    await db.insert(
      'progress',
      progress.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> reset(String bookId) async {
    final db = await _database;
    await db.delete('progress', where: 'book_id = ?', whereArgs: [bookId]);
  }

  // ---------------- Bookmarks ----------------

  Future<List<Bookmark>> getBookmarks(String bookId) async {
    final db = await _database;
    final rows = await db.query(
      'bookmarks',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'file_index, position_ms',
    );
    return rows.map(Bookmark.fromMap).toList();
  }

  Future<void> addBookmark(Bookmark bookmark) async {
    final db = await _database;
    await db.insert('bookmarks', bookmark.toMap());
  }

  Future<void> updateBookmarkNote(int id, String note) async {
    final db = await _database;
    await db.update('bookmarks', {'note': note},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteBookmark(int id) async {
    final db = await _database;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }
}
