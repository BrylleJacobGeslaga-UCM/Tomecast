import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/progress_store.dart';

/// Your own list of characters for a book (name + short note), handy for
/// big casts like Warcraft's.
class CharactersSheet extends StatefulWidget {
  final Book book;

  const CharactersSheet({super.key, required this.book});

  @override
  State<CharactersSheet> createState() => _CharactersSheetState();
}

class _CharactersSheetState extends State<CharactersSheet> {
  List<BookCharacter>? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ProgressStore.instance.getCharacters(widget.book.id);
    if (mounted) setState(() => _list = list);
  }

  Future<void> _edit([BookCharacter? existing]) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final note = TextEditingController(text: existing?.note ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add character' : 'Edit character'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Who they are',
                hintText: 'e.g. Red dragon, disguised as a mage',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save != true || name.text.trim().isEmpty) return;
    await ProgressStore.instance.saveCharacter(BookCharacter(
      id: existing?.id,
      bookId: widget.book.id,
      name: name.text.trim(),
      note: note.text.trim(),
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            Expanded(
              child: Text('Characters',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.person_add),
              label: const Text('Add'),
              onPressed: _edit,
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: list == null
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No characters yet.\n'
                          'Add names as you meet them so you never lose track.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final c = list[i];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(c.name.characters.first.toUpperCase()),
                          ),
                          title: Text(c.name),
                          subtitle: c.note.isEmpty ? null : Text(c.note),
                          onTap: () => _edit(c),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await ProgressStore.instance.deleteCharacter(c.id!);
                              await _load();
                            },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
