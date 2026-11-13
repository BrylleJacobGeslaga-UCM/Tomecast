import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/book.dart';
import '../utils/natural_sort.dart';
import 'read_along.dart';

/// Turns a root folder into a list of books.
/// Every subfolder of the root that contains audio files = one book.
/// Nested folders (e.g. "CD1", "CD2") inside a book are included in that book.
class LibraryScanner {
  static const audioExtensions = {
    '.mp3', '.m4a', '.m4b', '.aac', '.ogg', '.opus', '.flac', '.wav',
  };
  static const imageExtensions = {'.jpg', '.jpeg', '.png', '.webp'};
  static const preferredCoverNames = {'cover', 'folder', 'front', 'albumart'};

  Future<List<Book>> scan(String rootPath) async {
    final root = Directory(rootPath);
    if (!await root.exists()) return [];

    final books = <Book>[];

    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      if (p.basename(entity.path).startsWith('.')) continue; // skip hidden
      final book = await _scanBookFolder(entity);
      if (book != null) books.add(book);
    }

    books.sort((a, b) => naturalCompare(a.title, b.title));
    return books;
  }

  Future<Book?> _scanBookFolder(Directory dir) async {
    final audio = <String>[];
    final images = <String>[];
    final epubs = <String>[];

    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (audioExtensions.contains(ext)) {
          audio.add(entity.path);
        } else if (imageExtensions.contains(ext)) {
          images.add(entity.path);
        } else if (ext == '.epub') {
          epubs.add(entity.path);
        }
      }
    } on FileSystemException {
      return null; // folder we can't read
    }

    // A Storyteller-style EPUB (text + synced audio) makes this a
    // read-along book. Plain ebooks are ignored.
    epubs.sort(naturalCompare);
    for (final epub in epubs) {
      if (ReadAlong.hasMediaOverlays(epub)) {
        return Book(
          title: p.basename(dir.path),
          folderPath: dir.path,
          files: [], // filled in when the book is opened
          epubPath: epub,
          coverPath: _pickCover(images),
        );
      }
    }

    if (audio.isEmpty) return null;

    // Sort by path relative to the book folder so "CD1/..." comes before "CD2/..."
    audio.sort((a, b) => naturalCompare(
          p.relative(a, from: dir.path),
          p.relative(b, from: dir.path),
        ));

    return Book(
      title: p.basename(dir.path),
      folderPath: dir.path,
      files: audio,
      coverPath: _pickCover(images),
    );
  }

  String? _pickCover(List<String> images) {
    if (images.isEmpty) return null;
    // cover.jpg first, then folder.jpg, front.jpg, albumart.jpg
    for (final wanted in preferredCoverNames) {
      for (final img in images) {
        if (p.basenameWithoutExtension(img).toLowerCase() == wanted) return img;
      }
    }
    images.sort(naturalCompare);
    return images.first;
  }
}
