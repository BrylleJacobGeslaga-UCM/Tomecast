import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/book_progress.dart';
import '../models/bookmark.dart';

/// Local SQLite database: progress per book, bookmarks, listening history.
class ProgressStore {
  ProgressStore._();
  static final instance = ProgressStore._();

  Database? _db;

  Future<Database> get _database async {
    return _db ??= await openDatabase(
      p.join(await getDatabasesPath(), 'audiobooks.db'),
      version: 6,
      onCreate: (db, version) async {
        await _createProgressTable(db);
        await _createBookmarksTable(db);
        await _createListeningTable(db);
        await _createV4Tables(db);
        await _createQuotesTable(db);
        await _createV6Tables(db);
      },
      // Older installs get the new tables/columns added without losing data.
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createBookmarksTable(db);
        if (oldVersion < 3) {
          await db.execute(
              'ALTER TABLE progress ADD COLUMN finished_at INTEGER');
          await _createListeningTable(db);
        }
        if (oldVersion < 4) await _createV4Tables(db);
        if (oldVersion < 5) await _createQuotesTable(db);
        if (oldVersion < 6) await _createV6Tables(db);
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
          last_played INTEGER,
          finished_at INTEGER
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

  /// One row per minute (or less) of listening. Used for stats.
  static Future<void> _createListeningTable(Database db) async {
    await db.execute('''
      CREATE TABLE listening (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id     TEXT    NOT NULL,
        started_at  INTEGER NOT NULL,
        listened_ms INTEGER NOT NULL,
        speed       REAL    NOT NULL DEFAULT 1.0
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_listening_started ON listening(started_at)');
  }

  /// Character lists + cached file lengths/titles.
  static Future<void> _createV4Tables(Database db) async {
    await db.execute('''
      CREATE TABLE characters (
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL,
        name    TEXT NOT NULL,
        note    TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE file_info (
        path        TEXT PRIMARY KEY,
        size        INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL,
        title       TEXT
      )
    ''');
  }

  /// Quotes saved from the read-along text.
  static Future<void> _createQuotesTable(Database db) => db.execute('''
        CREATE TABLE quotes (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          book_id     TEXT    NOT NULL,
          text        TEXT    NOT NULL,
          note        TEXT    NOT NULL DEFAULT '',
          file_index  INTEGER,
          position_ms INTEGER,
          created_at  INTEGER NOT NULL
        )
      ''');

  /// Collections, ratings and "date added".
  static Future<void> _createV6Tables(Database db) async {
    await db.execute('''
      CREATE TABLE book_meta (
        book_id  TEXT PRIMARY KEY,
        added_at INTEGER NOT NULL,
        rating   INTEGER NOT NULL DEFAULT 0,
        review   TEXT    NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE collections (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        name       TEXT    NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE collection_books (
        collection_id INTEGER NOT NULL,
        book_id       TEXT    NOT NULL,
        PRIMARY KEY (collection_id, book_id)
      )
    ''');
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

  // ---------------- Listening history ----------------

  Future<void> addListening({
    required String bookId,
    required DateTime startedAt,
    required int listenedMs,
    required double speed,
  }) async {
    final db = await _database;
    await db.insert('listening', {
      'book_id': bookId,
      'started_at': startedAt.millisecondsSinceEpoch,
      'listened_ms': listenedMs,
      'speed': speed,
    });
  }

  Future<List<ListeningEntry>> getListening() async {
    final db = await _database;
    final rows = await db.query('listening', orderBy: 'started_at');
    return [
      for (final r in rows)
        ListeningEntry(
          bookId: r['book_id'] as String,
          startedAt:
              DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int),
          listened: Duration(milliseconds: r['listened_ms'] as int),
          speed: (r['speed'] as num).toDouble(),
        ),
    ];
  }

  // ---------------- Characters ----------------

  Future<List<BookCharacter>> getCharacters(String bookId) async {
    final db = await _database;
    final rows = await db.query('characters',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'name COLLATE NOCASE');
    return [
      for (final r in rows)
        BookCharacter(
          id: r['id'] as int,
          bookId: r['book_id'] as String,
          name: r['name'] as String,
          note: r['note'] as String,
        ),
    ];
  }

  Future<void> saveCharacter(BookCharacter c) async {
    final db = await _database;
    final row = {'book_id': c.bookId, 'name': c.name, 'note': c.note};
    if (c.id == null) {
      await db.insert('characters', row);
    } else {
      await db.update('characters', row, where: 'id = ?', whereArgs: [c.id]);
    }
  }

  Future<void> deleteCharacter(int id) async {
    final db = await _database;
    await db.delete('characters', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- File lengths + title tags (cache) ----------------

  /// Cached info for files whose size hasn't changed since.
  Future<Map<String, FileInfo>> getFileInfo(Map<String, int> pathSizes) async {
    final db = await _database;
    final result = <String, FileInfo>{};
    final paths = pathSizes.keys.toList();
    for (var i = 0; i < paths.length; i += 500) {
      final batch =
          paths.sublist(i, i + 500 < paths.length ? i + 500 : paths.length);
      final rows = await db.query('file_info',
          where: 'path IN (${List.filled(batch.length, '?').join(',')})',
          whereArgs: batch);
      for (final r in rows) {
        final path = r['path'] as String;
        if (r['size'] == pathSizes[path]) {
          result[path] = FileInfo(
            Duration(milliseconds: r['duration_ms'] as int),
            r['title'] as String?,
          );
        }
      }
    }
    return result;
  }

  Future<void> saveFileInfo(String path, int size, FileInfo info) async {
    final db = await _database;
    await db.insert(
      'file_info',
      {
        'path': path,
        'size': size,
        'duration_ms': info.duration.inMilliseconds,
        'title': info.title,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------- Quotes ----------------

  Future<List<Quote>> getQuotes(String bookId) async {
    final db = await _database;
    final rows = await db.query('quotes',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'created_at DESC');
    return rows.map(Quote.fromMap).toList();
  }

  Future<void> saveQuote(Quote q) async {
    final db = await _database;
    await db.insert('quotes', q.toMap());
  }

  Future<void> updateQuoteNote(int id, String note) async {
    final db = await _database;
    await db.update('quotes', {'note': note}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteQuote(int id) async {
    final db = await _database;
    await db.delete('quotes', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- Book info: date added, rating, review ----------------

  /// Records books seen for the first time (their "date added").
  Future<void> ensureAdded(Iterable<String> bookIds) async {
    final db = await _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final id in bookIds) {
      batch.insert('book_meta', {'book_id': id, 'added_at': now},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<Map<String, BookMeta>> getBookMeta() async {
    final db = await _database;
    final rows = await db.query('book_meta');
    return {
      for (final r in rows)
        r['book_id'] as String: BookMeta(
          addedAt: DateTime.fromMillisecondsSinceEpoch(r['added_at'] as int),
          rating: r['rating'] as int,
          review: r['review'] as String,
        ),
    };
  }

  Future<void> setRating(String bookId, int stars, String review) async {
    final db = await _database;
    await ensureAdded([bookId]);
    await db.update('book_meta', {'rating': stars, 'review': review},
        where: 'book_id = ?', whereArgs: [bookId]);
  }

  // ---------------- Collections ----------------

  Future<List<BookCollection>> getCollections() async {
    final db = await _database;
    final rows = await db.query('collections', orderBy: 'created_at');
    return [
      for (final r in rows) BookCollection(r['id'] as int, r['name'] as String),
    ];
  }

  Future<int> createCollection(String name) async {
    final db = await _database;
    return db.insert('collections', {
      'name': name,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> renameCollection(int id, String name) async {
    final db = await _database;
    await db.update('collections', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteCollection(int id) async {
    final db = await _database;
    await db.delete('collection_books', where: 'collection_id = ?', whereArgs: [id]);
    await db.delete('collections', where: 'id = ?', whereArgs: [id]);
  }

  /// book id → ids of the collections it's in.
  Future<Map<String, Set<int>>> getMemberships() async {
    final db = await _database;
    final rows = await db.query('collection_books');
    final result = <String, Set<int>>{};
    for (final r in rows) {
      result.putIfAbsent(r['book_id'] as String, () => {}).add(r['collection_id'] as int);
    }
    return result;
  }

  Future<void> setInCollection(int collectionId, String bookId, bool inside) async {
    final db = await _database;
    if (inside) {
      await db.insert('collection_books',
          {'collection_id': collectionId, 'book_id': bookId},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.delete('collection_books',
          where: 'collection_id = ? AND book_id = ?', whereArgs: [collectionId, bookId]);
    }
  }

  /// Known lengths of files (from the player's cache), ignoring file size.
  Future<Map<String, Duration>> getKnownDurations(List<String> paths) async {
    final db = await _database;
    final result = <String, Duration>{};
    for (var i = 0; i < paths.length; i += 500) {
      final batch =
          paths.sublist(i, i + 500 < paths.length ? i + 500 : paths.length);
      final rows = await db.query('file_info',
          columns: ['path', 'duration_ms'],
          where: 'path IN (${List.filled(batch.length, '?').join(',')})',
          whereArgs: batch);
      for (final r in rows) {
        result[r['path'] as String] = Duration(milliseconds: r['duration_ms'] as int);
      }
    }
    return result;
  }
}

class BookMeta {
  final DateTime addedAt;
  final int rating; // 0 = not rated, 1-5
  final String review;
  const BookMeta({required this.addedAt, this.rating = 0, this.review = ''});
}

class BookCollection {
  final int id;
  final String name;
  const BookCollection(this.id, this.name);
}

class Quote {
  final int? id;
  final String bookId;
  final String text;
  final String note;
  final int? fileIndex; // where it's spoken (null if not synced)
  final Duration? position;
  final DateTime createdAt;

  const Quote({
    this.id,
    required this.bookId,
    required this.text,
    this.note = '',
    this.fileIndex,
    this.position,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'book_id': bookId,
        'text': text,
        'note': note,
        'file_index': fileIndex,
        'position_ms': position?.inMilliseconds,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Quote.fromMap(Map<String, Object?> m) => Quote(
        id: m['id'] as int,
        bookId: m['book_id'] as String,
        text: m['text'] as String,
        note: m['note'] as String,
        fileIndex: m['file_index'] as int?,
        position: m['position_ms'] == null
            ? null
            : Duration(milliseconds: m['position_ms'] as int),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}

class BookCharacter {
  final int? id;
  final String bookId;
  final String name;
  final String note;

  const BookCharacter({
    this.id,
    required this.bookId,
    required this.name,
    this.note = '',
  });
}

class FileInfo {
  final Duration duration;
  final String? title;
  const FileInfo(this.duration, this.title);
}

class ListeningEntry {
  final String bookId;
  final DateTime startedAt;
  final Duration listened; // real time spent listening
  final double speed;

  const ListeningEntry({
    required this.bookId,
    required this.startedAt,
    required this.listened,
    required this.speed,
  });
}
