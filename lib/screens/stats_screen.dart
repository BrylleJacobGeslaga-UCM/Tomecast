import 'package:flutter/material.dart';

import '../services/stats_service.dart';
import '../utils/format.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  ListeningStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stats = await StatsService.load();
    if (mounted) setState(() => _stats = stats);
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    return Scaffold(
      appBar: AppBar(title: const Text('Listening stats')),
      body: stats == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: stats.isEmpty ? _empty() : _content(stats),
            ),
    );
  }

  Widget _empty() => ListView(
        children: const [
          SizedBox(height: 160),
          Icon(Icons.bar_chart, size: 72),
          SizedBox(height: 16),
          Text(
            'No listening yet.\nPlay a book and your stats show up here.',
            textAlign: TextAlign.center,
          ),
        ],
      );

  Widget _content(ListeningStats s) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---- Headline numbers ----
        Row(children: [
          _StatTile(label: 'Today', value: formatHours(s.today)),
          const SizedBox(width: 12),
          _StatTile(label: 'This week', value: formatHours(s.thisWeek)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _StatTile(
            label: 'Streak',
            value: '${s.currentStreak} day${s.currentStreak == 1 ? '' : 's'}',
            icon: Icons.local_fire_department,
          ),
          const SizedBox(width: 12),
          _StatTile(label: 'All time', value: formatHours(s.total)),
        ]),

        // ---- Last 7 days ----
        const SizedBox(height: 28),
        Text('Last 7 days', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        _WeekChart(days: s.last7Days, dates: s.last7Dates),

        // ---- Extra numbers ----
        const SizedBox(height: 20),
        _InfoRow('Last 30 days', formatHours(s.last30Days)),
        _InfoRow('Longest streak',
            '${s.longestStreak} day${s.longestStreak == 1 ? '' : 's'}'),
        if (s.averageSpeed != null)
          _InfoRow('Average speed', formatSpeed(s.averageSpeed!)),
        _InfoRow('Finished this month', '${s.finishedThisMonth}'),
        _InfoRow('Finished this year', '${s.finishedThisYear}'),

        // ---- Most listened ----
        if (s.topBooks.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('Most listened', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final b in s.topBooks)
            _BookTimeRow(book: b, max: s.topBooks.first.time),
        ],

        // ---- Finished ----
        if (s.finished.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('Finished books (${s.finished.length})',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final f in s.finished)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.check_circle,
                  color: theme.colorScheme.primary),
              title: Text(f.title),
              trailing: Text(
                f.date == null ? '—' : _formatDate(f.date!),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

/// Big number with a small label.
class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;

  const _StatTile({required this.label, required this.value, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Row(children: [
                if (icon != null) ...[
                  Icon(icon, size: 22, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(value,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simple bar chart: one bar per day. Tap a bar to see its exact time.
class _WeekChart extends StatefulWidget {
  final List<Duration> days;
  final List<DateTime> dates;

  const _WeekChart({required this.days, required this.dates});

  @override
  State<_WeekChart> createState() => _WeekChartState();
}

class _WeekChartState extends State<_WeekChart> {
  static const _chartHeight = 140.0;
  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  int _selected = 6; // today

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxMs = widget.days
        .map((d) => d.inMilliseconds)
        .fold<int>(0, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_selected == 6 ? 'Today' : _weekdayName(widget.dates[_selected])}: '
          '${formatHours(widget.days[_selected])}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _chartHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque, // whole column is tappable
                    onTap: () => setState(() => _selected = i),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 20,
                        // Days with no listening still show a thin baseline.
                        height: maxMs == 0
                            ? 2
                            : (widget.days[i].inMilliseconds / maxMs *
                                    _chartHeight)
                                .clamp(2.0, _chartHeight),
                        decoration: BoxDecoration(
                          color: i == _selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.primary.withValues(alpha: 0.45),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  _weekdays[widget.dates[i].weekday - 1],
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: i == _selected ? FontWeight.bold : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  static const _names = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  String _weekdayName(DateTime d) => _names[d.weekday - 1];
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _BookTimeRow extends StatelessWidget {
  final BookTime book;
  final Duration max;

  const _BookTimeRow({required this.book, required this.max});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(book.title, overflow: TextOverflow.ellipsis),
            ),
            Text(formatHours(book.time), style: theme.textTheme.bodySmall),
          ]),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: max.inMilliseconds == 0
                ? 0
                : book.time.inMilliseconds / max.inMilliseconds,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}
