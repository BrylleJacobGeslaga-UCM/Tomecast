import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';
import '../services/player_controller.dart';
import '../utils/format.dart';

class PlayerScreen extends StatefulWidget {
  final Book book;

  const PlayerScreen({super.key, required this.book});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final PlayerController _c = PlayerController(widget.book);

  /// While dragging the seek bar we show the drag position, not the player's.
  double? _dragMs;

  @override
  void initState() {
    super.initState();
    _c.init();
  }

  @override
  void dispose() {
    _c.dispose();
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
              TextButton(
                onPressed: _c.ready ? _showSpeedSheet : null,
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
    if (_c.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_c.error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (!_c.ready) {
      return const Center(child: CircularProgressIndicator());
    }

    return SafeArea(
      child: Column(
        children: [
          _overallProgress(),
          Expanded(
            child: Padding(
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
          onPressed: _c.previousFile,
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _showFilesSheet,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      p.basename(_c.currentFilePath),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const Icon(Icons.expand_more),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          iconSize: 32,
          icon: const Icon(Icons.skip_next),
          onPressed: _c.isLastFile ? null : _c.nextFile,
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _SkipButton(
          icon: Icons.fast_rewind,
          label: '1 m',
          onTap: () => _c.seekBy(const Duration(minutes: -1)),
        ),
        _SkipButton(
          icon: Icons.fast_rewind,
          label: '10 s',
          onTap: () => _c.seekBy(const Duration(seconds: -10)),
        ),
        IconButton.filled(
          iconSize: 48,
          padding: const EdgeInsets.all(12),
          icon: Icon(_c.isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: _c.togglePlay,
        ),
        _SkipButton(
          icon: Icons.fast_forward,
          label: '10 s',
          onTap: () => _c.seekBy(const Duration(seconds: 10)),
        ),
        _SkipButton(
          icon: Icons.fast_forward,
          label: '1 m',
          onTap: () => _c.seekBy(const Duration(minutes: 1)),
        ),
      ],
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

  void _showFilesSheet() {
    final files = widget.book.files;
    const tileHeight = 56.0;
    final controller = ScrollController(
      initialScrollOffset:
          (_c.fileIndex - 2).clamp(0, files.length).toDouble() * tileHeight,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: ListView.builder(
          controller: controller,
          itemCount: files.length,
          itemExtent: tileHeight,
          itemBuilder: (context, i) => ListTile(
            selected: i == _c.fileIndex,
            leading: Text('${i + 1}'),
            title: Text(
              p.relative(files[i], from: widget.book.folderPath),
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              Navigator.pop(context);
              _c.jumpToFile(i);
            },
          ),
        ),
      ),
    ).whenComplete(controller.dispose);
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
