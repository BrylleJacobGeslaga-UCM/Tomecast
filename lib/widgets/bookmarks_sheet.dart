import 'package:flutter/material.dart';

import '../models/book.dart';
import '../models/bookmark.dart';
import '../services/playback_service.dart';
import '../services/progress_store.dart';
import '../utils/format.dart';

/// Bookmarks for the current book: add one here, tap one to jump to it,
/// edit its note or delete it.
class BookmarksSheet extends StatefulWidget {
  final Book book;

  const BookmarksSheet({super.key, required this.book});

  @override
  State<BookmarksSheet> createState() => _BookmarksSheetState();
}

class _BookmarksSheetState extends State<BookmarksSheet> {
  final _service = PlaybackService.instance;
  List<Bookmark>? _bookmarks;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _service.getBookmarks();
    if (mounted) setState(() => _bookmarks = list);
  }

  Future<void> _add() async {
    final where = 'File ${_service.fileIndex + 1} · '
        '${formatDuration(_service.player.position)}';
    final note = await _askNote(title: 'Add bookmark', subtitle: where);
    if (note == null) return; // cancelled
    await _service.addBookmark(note);
    await _load();
  }

  Future<void> _edit(Bookmark b) async {
    final note = await _askNote(title: 'Edit note', initial: b.note);
    if (note == null) return;
    await ProgressStore.instance.updateBookmarkNote(b.id!, note.trim());
    await _load();
  }

  Future<void> _delete(Bookmark b) async {
    await ProgressStore.instance.deleteBookmark(b.id!);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Bookmark deleted'),
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () async {
          await ProgressStore.instance.addBookmark(b);
          await _load();
        },
      ),
    ));
  }

  /// Returns the typed note, '' for no note, or null if cancelled.
  Future<String?> _askNote({
    required String title,
    String? subtitle,
    String initial = '',
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle != null) ...[
              Text(subtitle),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bookmarks = _bookmarks;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text('Bookmarks', style: theme.textTheme.titleLarge),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.bookmark_add),
                label: const Text('Add here'),
                onPressed: _add,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: bookmarks == null
              ? const Center(child: CircularProgressIndicator())
              : bookmarks.isEmpty
                  ? const Center(child: Text('No bookmarks yet'))
                  : ListView.builder(
                      itemCount: bookmarks.length,
                      itemBuilder: (context, i) => _tile(bookmarks[i]),
                    ),
        ),
      ],
    );
  }

  Widget _tile(Bookmark b) {
    final where = 'File ${b.fileIndex + 1} · ${formatDuration(b.position)}';
    final hasNote = b.note.isNotEmpty;

    return ListTile(
      leading: const Icon(Icons.bookmark),
      title: Text(hasNote ? b.note : where,
          maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: hasNote ? Text(where) : null,
      onTap: () {
        Navigator.pop(context);
        _service.jumpTo(b.fileIndex, b.position);
      },
      trailing: PopupMenuButton<String>(
        onSelected: (v) => v == 'edit' ? _edit(b) : _delete(b),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit note')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}
