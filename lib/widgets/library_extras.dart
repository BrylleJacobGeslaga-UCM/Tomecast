import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/app_settings.dart';
import '../services/progress_store.dart';
import '../theme/tome_theme.dart';
import '../utils/book_sort.dart';

// =====================================================================
// Collections row above the shelves
// =====================================================================

class CollectionChips extends StatelessWidget {
  final List<BookCollection> collections;
  final int? selected;
  final void Function(int? id) onSelected;
  final VoidCallback onCreate;
  final void Function(BookCollection) onEdit;

  const CollectionChips({
    super.key,
    required this.collections,
    required this.selected,
    required this.onSelected,
    required this.onCreate,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.tome;
    Widget chip(String label, bool isSelected, VoidCallback onTap, {VoidCallback? onLongPress}) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onLongPress: onLongPress,
          child: ChoiceChip(
            label: Text(label),
            selected: isSelected,
            showCheckmark: false,
            labelStyle: TextStyle(color: isSelected ? p.trim : p.textMuted),
            side: BorderSide(color: isSelected ? p.trim : p.trimDark),
            onSelected: (_) => onTap(),
          ),
        ),
      );
    }

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        children: [
          chip('All books', selected == null, () => onSelected(null)),
          for (final c in collections)
            chip(c.name, selected == c.id, () => onSelected(c.id),
                onLongPress: () => onEdit(c)),
          ActionChip(
            avatar: Icon(Icons.add, size: 18, color: p.trim),
            label: Text('Collection', style: TextStyle(color: p.textMuted)),
            side: BorderSide(color: p.trimDark),
            onPressed: onCreate,
          ),
        ],
      ),
    );
  }
}

/// Small dialog asking for a name. Returns null if cancelled/empty.
Future<String?> askName(BuildContext context, {required String title, String initial = ''}) async {
  final controller = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'e.g. Warcraft Lore, Favorites'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  final trimmed = name?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// Tick the collections a book belongs to.
class BookCollectionsSheet extends StatefulWidget {
  final Book book;
  final List<BookCollection> collections;
  final Future<void> Function() onCreate;

  const BookCollectionsSheet({
    super.key,
    required this.book,
    required this.collections,
    required this.onCreate,
  });

  @override
  State<BookCollectionsSheet> createState() => _BookCollectionsSheetState();
}

class _BookCollectionsSheetState extends State<BookCollectionsSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Text('Collections', style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(widget.book.title, style: theme.textTheme.bodySmall),
          ),
          const Divider(height: 1),
          if (widget.collections.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No collections yet. Make one below.'),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in widget.collections)
                  CheckboxListTile(
                    title: Text(c.name),
                    value: widget.book.collectionIds.contains(c.id),
                    onChanged: (v) async {
                      final inside = v ?? false;
                      await ProgressStore.instance
                          .setInCollection(c.id, widget.book.id, inside);
                      setState(() => inside
                          ? widget.book.collectionIds.add(c.id)
                          : widget.book.collectionIds.remove(c.id));
                    },
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('New collection with this book'),
            onTap: () async {
              Navigator.pop(context);
              await widget.onCreate();
            },
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Sort
// =====================================================================

class SortSheet extends StatefulWidget {
  const SortSheet({super.key});

  @override
  State<SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<SortSheet> {
  final _s = AppSettings.instance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _s.sortBy;
    final asc = _s.sortAscending;

    return SafeArea(
      child: SingleChildScrollView(
       child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
            child: Row(
              children: [
                Expanded(child: Text('Sort by', style: theme.textTheme.titleLarge)),
                // Direction toggle
                TextButton.icon(
                  icon: Icon(asc ? Icons.arrow_upward : Icons.arrow_downward),
                  label: Text(_directionLabel(current, asc)),
                  onPressed: () => setState(() => _s.setSort(current, !asc)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final sort in BookSort.values)
            ListTile(
              title: Text(sort.label),
              trailing: sort == current ? Icon(Icons.check, color: context.tome.glow) : null,
              onTap: () => setState(() =>
                  _s.setSort(sort, sort == current ? asc : !sort.defaultDescending)),
            ),
          const SizedBox(height: 8),
        ],
       ),
      ),
    );
  }

  String _directionLabel(BookSort sort, bool asc) => switch (sort) {
        BookSort.title => asc ? 'A → Z' : 'Z → A',
        BookSort.recent || BookSort.added => asc ? 'Oldest first' : 'Newest first',
        BookSort.progress => asc ? 'Least read' : 'Most read',
        BookSort.rating => asc ? 'Lowest' : 'Highest',
        BookSort.length => asc ? 'Shortest' : 'Longest',
      };
}

// =====================================================================
// Rating
// =====================================================================

/// 1-5 stars plus an optional short review. Returns true if changed.
Future<bool> showRatingDialog(BuildContext context, Book book) async {
  var stars = book.rating;
  final review = TextEditingController(text: book.review);

  final save = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialog) => AlertDialog(
        title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StarRating(
              stars: stars,
              size: 38,
              onChanged: (v) => setDialog(() => stars = v == stars ? 0 : v),
            ),
            const SizedBox(height: 4),
            Text(stars == 0 ? 'Tap a star to rate' : _ratingWords[stars - 1],
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            TextField(
              controller: review,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Review (optional)',
                hintText: 'What did you think?',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    ),
  );
  if (save != true) return false;
  book.rating = stars;
  book.review = review.text.trim();
  await ProgressStore.instance.setRating(book.id, book.rating, book.review);
  return true;
}

const _ratingWords = [
  'Not for me',
  'It was okay',
  'Good tale',
  'Great tale',
  'Legendary',
];

/// Row of gold stars. With [onChanged] it can be tapped.
class StarRating extends StatelessWidget {
  final int stars;
  final double size;
  final ValueChanged<int>? onChanged;

  const StarRating({super.key, required this.stars, this.size = 14, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.tome;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          GestureDetector(
            onTap: onChanged == null ? null : () => onChanged!(i),
            child: Icon(
              i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: i <= stars ? p.trim : p.trimDark,
            ),
          ),
      ],
    );
  }
}
