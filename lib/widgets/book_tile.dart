import 'dart:io';

import 'package:flutter/material.dart';

import '../models/book.dart';

class BookTile extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;

  const BookTile({super.key, required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 110,
                height: 110,
                child: book.coverPath != null
                    ? Image.file(
                        File(book.coverPath!),
                        fit: BoxFit.cover,
                        cacheWidth: 300, // keeps memory low with big covers
                        errorBuilder: (_, __, ___) => _placeholder(theme),
                      )
                    : _placeholder(theme),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  ..._progressInfo(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _progressInfo(ThemeData theme) {
    final count = book.files.length;
    switch (book.status) {
      case BookStatus.newBook:
        return [
          Text('$count file${count == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall),
        ];
      case BookStatus.finished:
        return [
          Row(children: [
            Icon(Icons.check_circle, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text('Finished', style: theme.textTheme.bodySmall),
          ]),
        ];
      case BookStatus.started:
        return [
          Text('File ${book.currentFileIndex + 1} of $count',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: (book.currentFileIndex + 0.5) / count,
            borderRadius: BorderRadius.circular(4),
          ),
        ];
    }
  }

  Widget _placeholder(ThemeData theme) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(Icons.headphones, size: 40, color: theme.colorScheme.primary),
      );
}
