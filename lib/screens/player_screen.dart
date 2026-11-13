import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';
import '../services/app_settings.dart';
import '../services/live_sync.dart';
import '../services/playback_service.dart';
import '../utils/format.dart';
import '../widgets/bookmarks_sheet.dart';
import '../widgets/read_along_view.dart';

class PlayerScreen extends StatefulWidget {
  final Book book;

  const PlayerScreen({super.key, required this.book});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _c = PlaybackService.instance;

  /// While dragging the seek bar we show the drag position, not the player's.
  double? _dragMs;

  /// Read-along books open in text mode; the button switches to the cover.
  late bool _textMode = widget.book.readAlong != null;

  /// Live sync for books with an attached ebook (null until opened).
  LiveSync? _live;
  bool _openingLive = false;

  /// True once this screen's book is the one loaded in the player.
  bool get _ready => _c.book?.id == widget.book.id;

  @override
  void initState() {
    super.initState();
    // Keeps playing if this book is already loaded; otherwise loads it.
    _c.openBook(widget.book);
  }

  @override
  void dispose() {
    _live?.dispose(); // stops syncing; what's synced so far is saved
    // Don't stop the player: audio continues in the background.
    _c.save();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.book.title, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: _textMode ? 'Show cover' : 'Show text',
                icon: Icon(_textMode ? Icons.image_outlined : Icons.menu_book),
                onPressed: _ready ? _toggleText : null,
              ),
              IconButton(
                tooltip: 'Bookmarks',
                icon: const Icon(Icons.bookmark_border),
                onPressed: _ready ? _showBookmarksSheet : null,
              ),
              _sleepButton(),
              TextButton(
                onPressed: _ready ? _showSpeedSheet : null,
                child: Text(
                  formatSpeed(_c.speed),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          body: _buildBody(),
        );
      },
    );
  }

  Widget _buildBody() {
    if (_ready && _c.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_c.error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }

    return SafeArea(
      child: Column(
        children: [
          _overallProgress(),
          Expanded(
            child: _textMode
                ? _textView()
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(child: _cover()),
                  ),
          ),
          _fileSelector(),
          _seekBar(),
          const SizedBox(height: 8),
          _controls(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---------- Read-along text ----------

  Widget _textView() {
    final ready = widget.book.readAlong;
    if (ready != null) return ReadAlongView(sync: ready);
    final live = _live;
    if (live != null) return ReadAlongView(sync: live);
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Preparing the ebook text…'),
        ],
      ),
    );
  }

  Future<void> _toggleText() async {
    if (_textMode) {
      _live?.stop(); // no syncing while the text is hidden
      setState(() => _textMode = false);
      return;
    }
    // Storyteller book: already fully synced.
    if (widget.book.readAlong != null) {
      setState(() => _textMode = true);
      return;
    }
    // Normal audiobook: needs its ebook, synced live while you listen.
    if (!await LiveSync.hasEbook(widget.book)) {
      if (!await _askForEbook()) return;
    }
    if (_openingLive) return;
    setState(() {
      _textMode = true;
      _openingLive = true;
    });
    try {
      _live ??= await LiveSync.open(widget.book);
      _live!.start();
    } catch (e) {
      if (mounted) {
        setState(() => _textMode = false);
        _snack('Could not read the ebook: $e');
      }
    } finally {
      if (mounted) setState(() => _openingLive = false);
    }
  }

  /// Asks for the EPUB of this audiobook. Returns true if one was added.
  Future<bool> _askForEbook() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.menu_book),
        title: const Text('Add the ebook'),
        content: const Text(
          'Pick the EPUB of this audiobook. Tomecast matches the text to '
          'the narration a few minutes ahead of where you are listening, '
          'so the text can follow along.\n\n'
          'The first time, a speech model (about 140 MB) is downloaded. '
          'After that everything works offline.\n\n'
          'The EPUB must be DRM-free.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose EPUB'),
          ),
        ],
      ),
    );
    if (go != true) return false;

    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return false;
    final path = files.first.path;
    if (path == null || !path.toLowerCase().endsWith('.epub')) {
      _snack('Please choose an .epub file');
      return false;
    }
    await LiveSync.attachEbook(widget.book, path);
    return true;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- Top: whole-book progress ----------

  Widget _overallProgress() {
    final total = widget.book.files.length;
    return StreamBuilder<Duration>(
      stream: _c.player.positionStream,
      builder: (context, _) {
        final read = _c.filesRead;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: [
              LinearProgressIndicator(
                value: total == 0 ? 0 : read / total,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 6),
              Text('Read ${read.toStringAsFixed(1)} of $total files'),
            ],
          ),
        );
      },
    );
  }

  // ---------- Cover ----------

  Widget _cover() {
    final cover = widget.book.coverPath;
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: cover != null
            ? Image.file(File(cover), fit: BoxFit.cover)
            : Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.headphones, size: 96),
              ),
      ),
    );
  }

  // ---------- File name + prev/next file ----------

  Widget _fileSelector() {
    return Row(
      children: [
        IconButton(
          iconSize: 32,
          icon: const Icon(Icons.skip_previous),
          onPressed: _c.previous,
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _showFilesSheet,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              // Rebuilds with the position so the chapter name stays current.
              child: StreamBuilder<Duration>(
                stream: _c.player.positionStream,
                builder: (context, snap) {
                  final theme = Theme.of(context);
                  final fileName = p.basename(_c.currentFilePath);
                  final chapterIndex =
                      _c.chapterIndexAt(snap.data ?? Duration.zero);

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              chapterIndex >= 0
                                  ? _c.chapters[chapterIndex].title
                                  : fileName,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            if (chapterIndex >= 0)
                              Text(
                                'Chapter ${chapterIndex + 1} of '
                                '${_c.chapters.length} · $fileName',
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      const Icon(Icons.expand_more),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        IconButton(
          iconSize: 32,
          icon: const Icon(Icons.skip_next),
          onPressed: (_c.isLastFile && !_c.hasChapters) ? null : _c.next,
        ),
      ],
    );
  }

  // ---------- Seek bar ----------

  Widget _seekBar() {
    return StreamBuilder<Duration>(
      stream: _c.player.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = _c.player.duration ?? Duration.zero;
        final maxMs =
            dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
        final valueMs =
            (_dragMs ?? pos.inMilliseconds.toDouble()).clamp(0.0, maxMs);
        final shown = Duration(milliseconds: valueMs.round());

        return Column(
          children: [
            Slider(
              value: valueMs,
              max: maxMs,
              onChanged: (v) => setState(() => _dragMs = v),
              onChangeEnd: (v) async {
                await _c.seekTo(Duration(milliseconds: v.round()));
                if (mounted) setState(() => _dragMs = null);
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatDuration(shown)),
                  Text('-${formatDuration(dur - shown)}'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------- Skip buttons + play/pause ----------

  Widget _controls() {
    final settings = AppSettings.instance;
    final short = Duration(seconds: settings.shortSkipSeconds);
    final long = Duration(seconds: settings.longSkipSeconds);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _SkipButton(
          icon: Icons.fast_rewind,
          label: formatSkip(long),
          onTap: () => _c.seekBy(-long),
        ),
        _SkipButton(
          icon: Icons.fast_rewind,
          label: formatSkip(short),
          onTap: () => _c.seekBy(-short),
        ),
        IconButton.filled(
          iconSize: 48,
          padding: const EdgeInsets.all(12),
          icon: Icon(_c.isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: _c.togglePlay,
        ),
        _SkipButton(
          icon: Icons.fast_forward,
          label: formatSkip(short),
          onTap: () => _c.seekBy(short),
        ),
        _SkipButton(
          icon: Icons.fast_forward,
          label: formatSkip(long),
          onTap: () => _c.seekBy(long),
        ),
      ],
    );
  }

  // ---------- Sleep timer ----------

  Widget _sleepButton() {
    final theme = Theme.of(context);
    if (!_c.sleepTimerActive) {
      return IconButton(
        tooltip: 'Sleep timer',
        icon: const Icon(Icons.bedtime_outlined),
        onPressed: _ready ? _showSleepSheet : null,
      );
    }
    final label = _c.sleepAtEndOfFile
        ? 'End of file'
        : formatDuration(_c.sleepRemaining ?? Duration.zero);
    return TextButton.icon(
      onPressed: _showSleepSheet,
      icon: Icon(Icons.bedtime, color: theme.colorScheme.primary),
      label: Text(label),
    );
  }

  void _showSleepSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        void pick(VoidCallback action) {
          action();
          Navigator.pop(context);
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Sleep timer',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(AppSettings.instance.shakeToExtend
                    ? 'Counts down while playing. Shake the phone to reset it.'
                    : 'Counts down while playing.'),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final min in [5, 10, 15, 20, 30, 45, 60, 90])
                      ActionChip(
                        label: Text('$min min'),
                        onPressed: () => pick(() =>
                            _c.startSleepTimer(Duration(minutes: min))),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.skip_next, size: 18),
                      label: const Text('End of file'),
                      onPressed: () => pick(_c.startSleepAtEndOfFile),
                    ),
                  ],
                ),
                if (_c.sleepTimerActive) ...[
                  const SizedBox(height: 16),
                  TextButton.icon(
                    icon: const Icon(Icons.close),
                    label: const Text('Turn off timer'),
                    onPressed: () => pick(_c.cancelSleepTimer),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- Bottom sheets ----------

  void _showSpeedSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        var speed = _c.speed;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void set(double v) {
              setSheetState(() => speed = (v * 20).round() / 20);
              _c.setSpeed(v);
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(formatSpeed(speed),
                      style: Theme.of(context).textTheme.headlineMedium),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: speed > 0.5 ? () => set(speed - 0.05) : null,
                      ),
                      Expanded(
                        child: Slider(
                          value: speed.clamp(0.5, 3.0),
                          min: 0.5,
                          max: 3.0,
                          divisions: 50,
                          onChanged: set,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: speed < 3.0 ? () => set(speed + 0.05) : null,
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final preset in [0.8, 1.0, 1.25, 1.5, 1.75, 2.0])
                        ChoiceChip(
                          label: Text(formatSpeed(preset)),
                          selected: (speed - preset).abs() < 0.001,
                          onSelected: (_) => set(preset),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Files list, plus a Chapters tab when the current file has chapters.
  void _showFilesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final height = MediaQuery.of(context).size.height * 0.7;
        if (!_c.hasChapters) {
          return SizedBox(height: height, child: _filesList(context));
        }
        return SizedBox(
          height: height,
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(tabs: [
                  Tab(text: 'CHAPTERS'),
                  Tab(text: 'FILES'),
                ]),
                Expanded(
                  child: TabBarView(children: [
                    _chaptersList(context),
                    _filesList(context),
                  ]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static const _tileHeight = 56.0;

  Widget _filesList(BuildContext sheetContext) {
    final files = widget.book.files;
    return ListView.builder(
      controller: ScrollController(
        initialScrollOffset:
            (_c.fileIndex - 2).clamp(0, files.length).toDouble() * _tileHeight,
      ),
      itemCount: files.length,
      itemExtent: _tileHeight,
      itemBuilder: (context, i) => ListTile(
        selected: i == _c.fileIndex,
        leading: Text('${i + 1}'),
        title: Text(
          p.relative(files[i], from: widget.book.folderPath),
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () {
          Navigator.pop(sheetContext);
          _c.jumpToFile(i);
        },
      ),
    );
  }

  Widget _chaptersList(BuildContext sheetContext) {
    final chapters = _c.chapters;
    final current = _c.chapterIndexAt(_c.player.position);
    return ListView.builder(
      controller: ScrollController(
        initialScrollOffset:
            (current - 2).clamp(0, chapters.length).toDouble() * _tileHeight,
      ),
      itemCount: chapters.length,
      itemExtent: _tileHeight,
      itemBuilder: (context, i) => ListTile(
        selected: i == current,
        leading: Text('${i + 1}'),
        title: Text(chapters[i].title, overflow: TextOverflow.ellipsis),
        trailing: Text(formatDuration(chapters[i].start)),
        onTap: () {
          Navigator.pop(sheetContext);
          _c.seekTo(chapters[i].start);
        },
      ),
    );
  }

  void _showBookmarksSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: BookmarksSheet(book: widget.book),
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SkipButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(32),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32),
            Text(label),
          ],
        ),
      ),
    );
  }
}
