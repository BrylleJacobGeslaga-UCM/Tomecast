import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/playback_service.dart';
import '../services/text_sync.dart';

/// Shows the book's text and highlights the sentence being read.
/// Scrolls along with the narration; tap any sentence to jump there.
///
/// Works for both ready-made Storyteller EPUBs and live-synced ebooks.
class ReadAlongView extends StatefulWidget {
  final TextSync sync;

  const ReadAlongView({super.key, required this.sync});

  @override
  State<ReadAlongView> createState() => _ReadAlongViewState();
}

class _ReadAlongViewState extends State<ReadAlongView> {
  final _service = PlaybackService.instance;
  final _scroll = ScrollController();
  final _paragraphKeys = <int, GlobalKey>{};
  final _taps = <int, TapGestureRecognizer>{};
  StreamSubscription<Duration>? _sub;

  int _active = -1; // sentence being read
  int? _chapter; // chapter on screen (null = place not found yet)
  DateTime _lastUserScroll = DateTime.fromMillisecondsSinceEpoch(0);

  TextSync get _sync => widget.sync;

  @override
  void initState() {
    super.initState();
    _chapter = _sync.chapterForFile(_service.fileIndex);
    _update();
    _sub = _service.player.positionStream.listen((_) => _update());
    _sync.changes?.addListener(_onSyncChanged);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sync.changes?.removeListener(_onSyncChanged);
    _scroll.dispose();
    _clearTaps();
    super.dispose();
  }

  void _onSyncChanged() {
    // More of the book got synced, or the status line changed.
    _chapter ??= _sync.chapterForFile(_service.fileIndex);
    _active = -2; // force _update to re-check
    _update();
  }

  void _clearTaps() {
    for (final t in _taps.values) {
      t.dispose();
    }
    _taps.clear();
  }

  void _update() {
    if (!mounted) return;
    final s = _sync.sentenceAt(_service.fileIndex, _service.player.position);
    if (s == _active) return;

    final newChapter = s >= 0 ? _sync.sentenceChapter[s] : _chapter;
    final chapterChanged = newChapter != _chapter;
    setState(() {
      _active = s;
      if (chapterChanged) {
        _chapter = newChapter;
        _paragraphKeys.clear();
        _clearTaps();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (chapterChanged && _scroll.hasClients) _scroll.jumpTo(0);
      _scrollToActive(force: chapterChanged);
    });
  }

  void _scrollToActive({bool force = false}) {
    final chapter = _chapter;
    if (_active < 0 || chapter == null) return;
    // You scrolled by hand in the last 5 seconds: don't fight you.
    if (!force &&
        DateTime.now().difference(_lastUserScroll) <
            const Duration(seconds: 5)) {
      return;
    }
    final paragraphs = _sync.chapters[chapter].paragraphs;
    final index = paragraphs.indexWhere((p) => p.sentences.contains(_active));
    final context = _paragraphKeys[index]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.3, // active paragraph about a third from the top
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  TapGestureRecognizer _tapFor(int sentence) {
    return _taps.putIfAbsent(sentence, () {
      return TapGestureRecognizer()
        ..onTap = () {
          final where = _sync.timeOfSentence(sentence);
          if (where == null) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("This part isn't synced yet"),
              duration: Duration(seconds: 2),
            ));
            return;
          }
          _lastUserScroll = DateTime.fromMillisecondsSinceEpoch(0);
          _service.jumpTo(where.file, where.time);
        };
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _sync.status;

    final banner = status == null
        ? null
        : Container(
            width: double.infinity,
            color: theme.colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(status, style: theme.textTheme.bodySmall),
              ),
            ]),
          );

    final chapterIndex = _chapter;
    Widget body;
    if (_sync.chapters.isEmpty) {
      body = const Center(child: Text('No text found in this book'));
    } else if (chapterIndex == null) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Finding your place in the book…\n'
            'Keep listening; the text appears once a few sentences are matched.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      body = _chapterText(theme, chapterIndex);
    }

    return Column(
      children: [
        if (banner != null) banner,
        Expanded(child: body),
      ],
    );
  }

  Widget _chapterText(ThemeData theme, int chapterIndex) {
    final chapter = _sync.chapters[chapterIndex];
    final bodyStyle = theme.textTheme.bodyLarge?.copyWith(
      fontSize: 19,
      height: 1.6,
    );
    final headingStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.bold,
      height: 1.4,
    );
    final activeStyle = TextStyle(
      backgroundColor: theme.colorScheme.primaryContainer,
      color: theme.colorScheme.onPrimaryContainer,
    );

    return NotificationListener<UserScrollNotification>(
      onNotification: (_) {
        _lastUserScroll = DateTime.now();
        return false;
      },
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Section ${chapterIndex + 1} of ${_sync.chapters.length}',
                style: theme.textTheme.labelMedium,
              ),
            ),
            for (var i = 0; i < chapter.paragraphs.length; i++)
              Padding(
                key: _paragraphKeys.putIfAbsent(i, GlobalKey.new),
                padding: const EdgeInsets.only(bottom: 16),
                child: Text.rich(
                  TextSpan(
                    style: chapter.paragraphs[i].heading
                        ? headingStyle
                        : bodyStyle,
                    children: [
                      for (final s in chapter.paragraphs[i].sentences)
                        TextSpan(
                          text: '${_sync.sentenceText(s)} ',
                          style: s == _active ? activeStyle : null,
                          recognizer: _tapFor(s),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
