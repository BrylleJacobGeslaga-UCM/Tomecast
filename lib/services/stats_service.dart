import 'package:path/path.dart' as p;

import 'progress_store.dart';

class BookTime {
  final String title;
  final Duration time;
  const BookTime(this.title, this.time);
}

class FinishedBook {
  final String title;
  final DateTime? date; // null for books finished before stats existed
  const FinishedBook(this.title, this.date);
}

class ListeningStats {
  final Duration today;
  final Duration thisWeek;
  final Duration last30Days;
  final Duration total;

  /// Listening per day for the last 7 days. Index 6 = today.
  final List<Duration> last7Days;
  final List<DateTime> last7Dates;

  final int currentStreak;
  final int longestStreak;
  final double? averageSpeed; // null if nothing listened yet

  final List<BookTime> topBooks;
  final List<FinishedBook> finished;
  final int finishedThisMonth;
  final int finishedThisYear;

  const ListeningStats({
    required this.today,
    required this.thisWeek,
    required this.last30Days,
    required this.total,
    required this.last7Days,
    required this.last7Dates,
    required this.currentStreak,
    required this.longestStreak,
    required this.averageSpeed,
    required this.topBooks,
    required this.finished,
    required this.finishedThisMonth,
    required this.finishedThisYear,
  });

  bool get isEmpty => total == Duration.zero && finished.isEmpty;
}

/// Turns the raw listening history into the numbers on the stats screen.
class StatsService {
  /// A day counts toward the streak with at least this much listening.
  static const streakMinimum = Duration(minutes: 1);

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  /// Book id → title. Ids are folder paths, or EPUB paths for read-along.
  static String _title(String id) => id.toLowerCase().endsWith('.epub')
      ? p.basenameWithoutExtension(id)
      : p.basename(id);

  static Future<ListeningStats> load() async {
    final store = ProgressStore.instance;
    final entries = await store.getListening();
    final progress = await store.getAll();

    final now = DateTime.now();
    final today = _day(now);
    final weekStart = today.subtract(Duration(days: today.weekday - 1)); // Monday
    final monthAgo = today.subtract(const Duration(days: 29));

    var total = Duration.zero;
    var thisWeek = Duration.zero;
    var last30 = Duration.zero;
    final perDay = <DateTime, Duration>{};
    final perBook = <String, Duration>{};
    var speedWeighted = 0.0;

    for (final e in entries) {
      final day = _day(e.startedAt);
      total += e.listened;
      perDay[day] = (perDay[day] ?? Duration.zero) + e.listened;
      perBook[e.bookId] = (perBook[e.bookId] ?? Duration.zero) + e.listened;
      speedWeighted += e.speed * e.listened.inMilliseconds;
      if (!day.isBefore(weekStart)) thisWeek += e.listened;
      if (!day.isBefore(monthAgo)) last30 += e.listened;
    }

    // Last 7 days
    final dates = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    final last7 = [for (final d in dates) perDay[d] ?? Duration.zero];

    // Streaks
    final activeDays = perDay.entries
        .where((e) => e.value >= streakMinimum)
        .map((e) => e.key)
        .toSet();

    var current = 0;
    // A streak is still alive if you listened today OR yesterday.
    var cursor = activeDays.contains(today)
        ? today
        : today.subtract(const Duration(days: 1));
    while (activeDays.contains(cursor)) {
      current++;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }

    var longest = 0;
    var run = 0;
    DateTime? previous;
    final sortedDays = activeDays.toList()..sort();
    for (final d in sortedDays) {
      final isNextDay = previous != null &&
          DateTime(previous.year, previous.month, previous.day + 1) == d;
      run = isNextDay ? run + 1 : 1;
      if (run > longest) longest = run;
      previous = d;
    }

    // Most listened books
    final top = perBook.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topBooks = [
      for (final e in top.take(5)) BookTime(_title(e.key), e.value),
    ];

    // Finished books, newest first
    final finished = progress.values.where((pr) => pr.finished).toList()
      ..sort((a, b) => (b.finishedAt ?? DateTime(0))
          .compareTo(a.finishedAt ?? DateTime(0)));
    final finishedBooks = [
      for (final pr in finished)
        FinishedBook(_title(pr.bookId), pr.finishedAt),
    ];
    final thisMonth = finished.where((pr) =>
        pr.finishedAt != null &&
        pr.finishedAt!.year == now.year &&
        pr.finishedAt!.month == now.month);
    final thisYear =
        finished.where((pr) => pr.finishedAt?.year == now.year);

    return ListeningStats(
      today: perDay[today] ?? Duration.zero,
      thisWeek: thisWeek,
      last30Days: last30,
      total: total,
      last7Days: last7,
      last7Dates: dates,
      currentStreak: current,
      longestStreak: longest,
      averageSpeed: total.inMilliseconds == 0
          ? null
          : speedWeighted / total.inMilliseconds,
      topBooks: topBooks,
      finished: finishedBooks,
      finishedThisMonth: thisMonth.length,
      finishedThisYear: thisYear.length,
    );
  }
}
