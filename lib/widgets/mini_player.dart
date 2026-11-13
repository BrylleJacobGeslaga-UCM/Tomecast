import 'dart:io';

import 'package:flutter/material.dart';

import '../services/playback_service.dart';

/// Small bar at the bottom of the library showing the current book.
class MiniPlayer extends StatelessWidget {
  final VoidCallback onOpen;

  const MiniPlayer({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final service = PlaybackService.instance;
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final book = service.book;
        if (book == null) return const SizedBox.shrink();

        return Material(
          color: theme.colorScheme.surfaceContainerHigh,
          child: InkWell(
            onTap: onOpen,
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 64,
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: book.coverPath != null
                          ? Image.file(File(book.coverPath!),
                              fit: BoxFit.cover, cacheWidth: 200)
                          : const Icon(Icons.headphones),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall),
                          Text(
                            'File ${service.fileIndex + 1} of ${book.files.length}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      iconSize: 36,
                      icon: Icon(service.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled),
                      onPressed: service.togglePlay,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
