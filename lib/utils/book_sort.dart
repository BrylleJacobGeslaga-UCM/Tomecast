import '../models/book.dart';
import 'natural_sort.dart';

/// How the library can be sorted.
enum BookSort { title, recent, added, progress, rating, length }

extension BookSortLabel on BookSort {
  String get label => switch (this) {
        BookSort.title => 'Title',
        BookSort.recent => 'Recently played',
        BookSort.added => 'Date added',
        BookSort.progress => 'Progress',
        BookSort.rating => 'Rating',
        BookSort.length => 'Length',
      };

  /// Most people want newest/highest/longest first for these.
  bool get defaultDescending => this != BookSort.title;
}

double _progress(Book b) {
  if (b.finished) return 1;
  if (b.files.isEmpty) return 0;
  return (b.currentFileIndex + (b.position > Duration.zero ? 0.5 : 0)) / b.files.length;
}

/// Sorts a copy of [books]. Ties (and books without the value, like
/// unknown length) fall back to title order.
List<Book> sortBooks(List<Book> books, BookSort sort, {required bool ascending}) {
  int byTitle(Book a, Book b) => naturalCompare(a.title, b.title);

  int compare(Book a, Book b) {
    final dir = ascending ? 1 : -1;
    switch (sort) {
      case BookSort.title:
        return dir * byTitle(a, b);
      case BookSort.recent:
        final x = a.lastPlayed, y = b.lastPlayed;
        if (x == null && y == null) return byTitle(a, b);
        if (x == null) return 1; // never played: always last
        if (y == null) return -1;
        return dir * x.compareTo(y);
      case BookSort.added:
        final x = a.addedAt ?? DateTime(0), y = b.addedAt ?? DateTime(0);
        return dir * x.compareTo(y);
      case BookSort.progress:
        return dir * _progress(a).compareTo(_progress(b));
      case BookSort.rating:
        if (a.rating == 0 && b.rating == 0) return byTitle(a, b);
        if (a.rating == 0) return 1; // unrated: always last
        if (b.rating == 0) return -1;
        return dir * a.rating.compareTo(b.rating);
      case BookSort.length:
        final x = a.knownLength, y = b.knownLength;
        if (x == null && y == null) return byTitle(a, b);
        if (x == null) return 1; // unknown length: always last
        if (y == null) return -1;
        return dir * x.compareTo(y);
    }
  }

  return [...books]..sort((a, b) {
      final c = compare(a, b);
      return c != 0 ? c : byTitle(a, b);
    });
}
