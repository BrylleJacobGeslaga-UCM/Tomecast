import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/book.dart';
import '../services/playback_service.dart';
import '../services/progress_store.dart';
import '../services/text_sync.dart';
import '../theme/tome_theme.dart';
import '../utils/format.dart';

/// Opened by long-pressing a sentence in the read-along text.
/// Lets you extend the quote to the next sentences, add a note, and save.
/// Returns true if a quote was saved.
Future<bool> showSaveQuoteSheet(
  BuildContext context, {
  required TextSync sync,
  required int sentence,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SaveQuoteSheet(sync: sync, first: sentence),
  );
  return saved == true;
}

class _SaveQuoteSheet extends StatefulWidget {
  final TextSync sync;
  final int first;

  const _SaveQuoteSheet({required this.sync, required this.first});

  @override
  State<_SaveQuoteSheet> createState() => _SaveQuoteSheetState();
}

class _SaveQuoteSheetState extends State<_SaveQuoteSheet> {
  static const _maxSentences = 8;
  int _count = 1; // how many sentences, starting at `first`
  final _note = TextEditingController();

  int get _total => widget.sync.sentenceChapter.length;

  String get _text => [
        for (var s = widget.first; s < widget.first + _count && s < _total; s++)
          widget.sync.sentenceText(s),
      ].join(' ');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final service = PlaybackService.instance;
    final book = service.book;
    if (book == null) return;
    // Where the quote is spoken; if not synced (yet), use where you are now.
    final where = widget.sync.timeOfSentence(widget.first);
    await ProgressStore.instance.saveQuote(Quote(
      bookId: book.id,
      text: _text,
      note: _note.text.trim(),
      fileIndex: where?.file ?? service.fileIndex,
      position: where?.time ?? service.player.position,
      createdAt: DateTime.now(),
    ));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.tome;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Save quote', style: theme.textTheme.titleLarge?.copyWith(color: p.trim)),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.35),
            child: SingleChildScrollView(child: QuoteText(_text)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Sentences: $_count', style: theme.textTheme.bodySmall),
              const Spacer(),
              IconButton(
                tooltip: 'One sentence less',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _count > 1 ? () => setState(() => _count--) : null,
              ),
              IconButton(
                tooltip: 'Add the next sentence',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: _count < _maxSentences && widget.first + _count < _total
                    ? () => setState(() => _count++)
                    : null,
              ),
            ],
          ),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'Why you saved it',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.format_quote),
            label: const Text('Save quote'),
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// A quote styled like a passage from a tome: gold bar, italic serif.
class QuoteText extends StatelessWidget {
  final String text;

  const QuoteText(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.tome;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: p.trim, width: 3)),
        color: p.glow.withValues(alpha: p.dark ? 0.06 : 0.04),
      ),
      child: Text(
        '“$text”',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontStyle: FontStyle.italic,
              height: 1.45,
              color: p.text,
            ),
      ),
    );
  }
}

/// All saved quotes of a book: tap to listen again, copy, edit, delete.
class QuotesSheet extends StatefulWidget {
  final Book book;

  const QuotesSheet({super.key, required this.book});

  @override
  State<QuotesSheet> createState() => _QuotesSheetState();
}

class _QuotesSheetState extends State<QuotesSheet> {
  List<Quote>? _quotes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ProgressStore.instance.getQuotes(widget.book.id);
    if (mounted) setState(() => _quotes = list);
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _meta(Quote q) {
    final parts = <String>[];
    if (q.fileIndex != null && q.position != null) {
      parts.add('File ${q.fileIndex! + 1} · ${formatDuration(q.position!)}');
    }
    final d = q.createdAt;
    parts.add('${_months[d.month - 1]} ${d.day}, ${d.year}');
    return parts.join('  ·  ');
  }

  Future<void> _editNote(Quote q) async {
    final controller = TextEditingController(text: q.note);
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
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
    if (note == null) return;
    await ProgressStore.instance.updateQuoteNote(q.id!, note.trim());
    await _load();
  }

  Future<void> _delete(Quote q) async {
    await ProgressStore.instance.deleteQuote(q.id!);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Quote deleted'),
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () async {
          await ProgressStore.instance.saveQuote(q);
          await _load();
        },
      ),
    ));
  }

  void _copy(Quote q) {
    Clipboard.setData(ClipboardData(text: '“${q.text}”\n— ${widget.book.title}'));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quote copied')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.tome;
    final quotes = _quotes;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Row(children: [
            Icon(Icons.format_quote, color: p.trim),
            const SizedBox(width: 8),
            Text('Quotes', style: theme.textTheme.titleLarge?.copyWith(color: p.trim)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: quotes == null
              ? const Center(child: CircularProgressIndicator())
              : quotes.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Text(
                          'No quotes yet.\n\nIn read-along mode, long-press any '
                          'sentence to save it here.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: quotes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 18),
                      itemBuilder: (context, i) {
                        final q = quotes[i];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: q.fileIndex == null || q.position == null
                                  ? null
                                  : () {
                                      Navigator.pop(context);
                                      PlaybackService.instance
                                          .jumpTo(q.fileIndex!, q.position!);
                                    },
                              child: QuoteText(q.text),
                            ),
                            if (q.note.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(17, 6, 0, 0),
                                child: Text(q.note, style: theme.textTheme.bodyMedium),
                              ),
                            Row(
                              children: [
                                const SizedBox(width: 17),
                                Expanded(
                                  child: Text(_meta(q), style: theme.textTheme.bodySmall),
                                ),
                                IconButton(
                                  tooltip: 'Copy',
                                  icon: const Icon(Icons.copy, size: 20),
                                  onPressed: () => _copy(q),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (v) =>
                                      v == 'note' ? _editNote(q) : _delete(q),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'note', child: Text('Edit note')),
                                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
