import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/book_progress.dart';

/// Saves where you are in each book to a local SQLite database.
/// Bookmarks and listening stats will get their own tables in later steps.
class ProgressStore {
  ProgressStore._();
  static final instance = ProgressStore._();

  Database? _db;

  Future<Database> get _database async {
    return _db ??= await openDatabase(
      p.join(await getDatabasesPath(), 'audiobooks.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE progress (
            book_id     TEXT PRIMARY KEY,
            file_index  INTEGER NOT NULL DEFAULT 0,
            position_ms INTEGER NOT NULL DEFAULT 0,
            finished    INTEGER NOT NULL DEFAULT 0,
            speed       REAL    NOT NULL DEFAULT 1.0,
            last_played INTEGER
          )
        ''');
      },
    );
  }

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
}
