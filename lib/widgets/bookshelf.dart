import 'dart:io';

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../theme/ornaments.dart';
import '../theme/tome_theme.dart';

/// Books standing on shelves, three per shelf.
class Bookshelf extends StatelessWidget {
  final List<Book> books;
  final void Function(Book) onTap;
  final void Function(Book) onLongPress;
  final Widget? header;

  const Bookshelf({
    super.key,
    required this.books,
    required this.onTap,
    required this.onLongPress,
    this.header,
  });

  static const perShelf = 3;

  @override
  Widget build(BuildContext context) {
    final shelves = (books.length + perShelf - 1) ~/ perShelf;
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: shelves + (header == null ? 0 : 1),
      itemBuilder: (context, i) {
        if (header != null) {
          if (i == 0) return header!;
          i -= 1;
        }
        final start = i * perShelf;
        final row = books.sublist(start, (start + perShelf).clamp(0, books.length).toInt());
        return _Shelf(books: row, onTap: onTap, onLongPress: onLongPress);
      },
    );
  }
}

class _Shelf extends StatelessWidget {
  final List<Book> books;
  final void Function(Book) onTap;
  final void Function(Book) onLongPress;

  const _Shelf({required this.books, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final p = context.tome;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < Bookshelf.perShelf; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: i < books.length
                          ? _ShelfBook(
                              book: books[i],
                              onTap: () => onTap(books[i]),
                              onLongPress: () => onLongPress(books[i]),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          ),
          // The plank
          Container(
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color.lerp(p.shelf, Colors.white, 0.12)!, p.shelf, p.shelfEdge],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: p.dark ? 0.6 : 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelfBook extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ShelfBook({required this.book, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final p = context.tome;
    final theme = Theme.of(context);
    final count = book.files.length;
    final progress = switch (book.status) {
      BookStatus.finished => 1.0,
      BookStatus.newBook => 0.0,
      BookStatus.started => count == 0 ? 0.0 : (book.currentFileIndex + 0.5) / count,
    };

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 0.72,
                child: OrnateFrame(
                  radius: 6,
                  thickness: 1.6,
                  glow: book.status == BookStatus.started,
                  child: book.coverPath != null
                      ? Image.file(
                          File(book.coverPath!),
                          fit: BoxFit.cover,
                          cacheWidth: 360,
                          errorBuilder: (_, __, ___) =>
                              TomeCoverPlaceholder(title: book.title),
                        )
                      : TomeCoverPlaceholder(title: book.title),
                ),
              ),
              // Badges: finished seal / read-along
              if (book.status == BookStatus.finished)
                Positioned(right: 4, top: 4, child: _Seal(icon: Icons.check, color: p.glow)),
              if (book.isReadAlong)
                Positioned(left: 4, top: 4, child: _Seal(icon: Icons.menu_book, color: p.trim)),
            ],
          ),
          const SizedBox(height: 6),
          // Progress glow line
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(value: progress, minHeight: 3),
          ),
          const SizedBox(height: 4),
          // Always the height of 2 lines, so every book on a shelf lines up.
          SizedBox(
            // (scaled by the phone's font size setting)
            height: 2 * 1.15 *
                    MediaQuery.textScalerOf(context)
                        .scale(theme.textTheme.bodySmall?.fontSize ?? 13.5) +
                4,
            child: Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: p.text, height: 1.15),
            ),
          ),
        ],
      ),
    );
  }
}

class _Seal extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _Seal({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final p = context.tome;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.bgBottom.withValues(alpha: 0.85),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Icon(icon, size: 13, color: color),
    );
  }
}

/// "Continue listening" card at the top of the library.
class ContinueCard extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;

  const ContinueCard({super.key, required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.tome;
    final theme = Theme.of(context);
    final count = book.files.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: p.surface.withValues(alpha: p.dark ? 0.75 : 0.9),
            border: Border.all(color: p.trim.withValues(alpha: 0.7)),
            boxShadow: [
              BoxShadow(color: p.glow.withValues(alpha: p.dark ? 0.18 : 0.1), blurRadius: 24),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                height: 100,
                child: OrnateFrame(
                  radius: 5,
                  thickness: 1.5,
                  child: book.coverPath != null
                      ? Image.file(File(book.coverPath!), fit: BoxFit.cover, cacheWidth: 240)
                      : TomeCoverPlaceholder(title: book.title),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CONTINUE YOUR TALE',
                        style: titleFont(theme.textTheme.labelSmall)
                            .copyWith(color: p.trim, letterSpacing: 1.5)),
                    const SizedBox(height: 4),
                    Text(book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: count == 0 ? 0 : (book.currentFileIndex + 0.5) / count,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    const SizedBox(height: 4),
                    Text(count == 0 ? '' : 'File ${book.currentFileIndex + 1} of $count',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.play_circle_fill, size: 44, color: p.glow),
            ],
          ),
        ),
      ),
    );
  }
}
