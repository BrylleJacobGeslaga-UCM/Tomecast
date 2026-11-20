import 'dart:io';

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../theme/ornaments.dart';
import 'library_extras.dart';

class BookTile extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const BookTile({
    super.key,
    required this.book,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
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
    return [
      if (book.isReadAlong)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Icon(Icons.menu_book, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text('Read-along', style: theme.textTheme.bodySmall),
          ]),
        ),
      ..._statusInfo(theme),
      if (book.rating > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: StarRating(stars: book.rating, size: 14),
        ),
    ];
  }

  List<Widget> _statusInfo(ThemeData theme) {
    final count = book.files.length;
    if (count == 0) return const []; // read-along book not opened yet
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

  Widget _placeholder(ThemeData theme) => TomeCoverPlaceholder(title: book.title);
}
