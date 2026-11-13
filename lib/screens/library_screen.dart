import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/app_settings.dart';
import '../services/folder_access.dart';
import '../services/library_scanner.dart';
import '../services/live_sync.dart';
import '../services/playback_service.dart';
import '../services/progress_store.dart';
import '../services/read_along.dart';
import '../widgets/book_tile.dart';
import '../widgets/mini_player.dart';
import 'player_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _scanner = LibraryScanner();

  String? _rootFolder;
  List<Book> _books = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _rootFolder = AppSettings.instance.rootFolder;
    if (_rootFolder != null && await FolderAccess.ensurePermission()) {
      await _scan();
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickRootFolder() async {
    try {
      final path = await FolderAccess.pickFolder();
      if (path == null) return;
      await AppSettings.instance.setRootFolder(path);
      _rootFolder = path;
      await _scan();
    } on FolderAccessException catch (e) {
      _showMessage(e.message);
    }
  }

  Future<void> _scan() async {
    if (_rootFolder == null) return;
    setState(() => _loading = true);
    final books = await _scanner.scan(_rootFolder!);
    final progress = await ProgressStore.instance.getAll();
    for (final book in books) {
      book.applyProgress(progress[book.id]);
    }
    // Keep the book that's playing as the same object, so the library
    // and the player always show the same progress.
    final playing = PlaybackService.instance.book;
    if (playing != null) {
      final i = books.indexWhere((b) => b.id == playing.id);
      if (i != -1) books[i] = playing;
    }
    // Read-along books already prepared this session stay ready.
    for (var i = 0; i < books.length; i++) {
      final old = _books.where((b) => b.id == books[i].id && b.isReady);
      if (books[i].isReadAlong && !books[i].isReady && old.isNotEmpty) {
        books[i] = old.first;
      }
    }
    PlaybackService.instance.library = books; // for "play next book"
    if (!mounted) return;
    setState(() {
      _books = books;
      _loading = false;
    });
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Library'),
          actions: [
            IconButton(
              tooltip: 'Rescan',
              icon: const Icon(Icons.refresh),
              onPressed: _rootFolder == null ? null : _scan,
            ),
            IconButton(
              tooltip: 'Stats',
              icon: const Icon(Icons.bar_chart),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StatsScreen()),
              ),
            ),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: _openSettings,
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'ALL'),
              Tab(text: 'NEW'),
              Tab(text: 'STARTED'),
              Tab(text: 'FINISHED'),
            ],
          ),
        ),
        body: _buildBody(),
        bottomNavigationBar: MiniPlayer(
          onOpen: () {
            final book = PlaybackService.instance.book;
            if (book != null) _openBook(book);
          },
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_rootFolder == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.library_music_outlined, size: 72),
              const SizedBox(height: 16),
              const Text(
                'Pick the folder where your audiobooks are.\n'
                'Each subfolder becomes one book.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _pickRootFolder,
                icon: const Icon(Icons.folder_open),
                label: const Text('Choose folder'),
              ),
            ],
          ),
        ),
      );
    }

    return TabBarView(
      children: [
        _bookList(_books),
        _bookList(_books.where((b) => b.status == BookStatus.newBook).toList()),
        _bookList(_startedBooks()),
        _bookList(_books.where((b) => b.status == BookStatus.finished).toList()),
      ],
    );
  }

  /// Started books, most recently played first.
  List<Book> _startedBooks() {
    final started =
        _books.where((b) => b.status == BookStatus.started).toList();
    started.sort((a, b) => (b.lastPlayed ?? DateTime(0))
        .compareTo(a.lastPlayed ?? DateTime(0)));
    return started;
  }

  Future<void> _openBook(Book book) async {
    if (!book.isReady) {
      final ok = await _prepareReadAlong(book);
      if (!ok || !mounted) return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerScreen(book: book)),
    );
    // The player updates the Book object directly, so just redraw.
    if (mounted) setState(() {});
  }

  /// First time a read-along book is opened: read its text + timings and
  /// copy the audio out of the EPUB. Shows progress while it works.
  Future<bool> _prepareReadAlong(Book book) async {
    final status = ValueNotifier<String>('Preparing…');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: status,
                builder: (_, text, __) => Text(text),
              ),
            ),
          ]),
        ),
      ),
    );

    try {
      final data = await ReadAlong.prepare(
        book.epubPath!,
        onProgress: (msg) => status.value = msg,
      );
      book.readAlong = data;
      book.files = data.audioFiles;
      book.currentFileIndex =
          book.currentFileIndex.clamp(0, book.files.length - 1);
      return true;
    } catch (e) {
      _showMessage('Could not open read-along book: $e');
      return false;
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _openSettings() async {
    final folderChanged = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (folderChanged == true) {
      _rootFolder = AppSettings.instance.rootFolder;
      await _scan();
    }
  }

  /// Long-press menu on a book.
  Future<void> _showBookMenu(Book book) async {
    final service = PlaybackService.instance;
    final hasEbook = !book.isReadAlong && await LiveSync.hasEbook(book);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(book.title,
                  style: Theme.of(sheetContext).textTheme.titleMedium),
              subtitle: Text('${book.files.length} files'),
            ),
            const Divider(height: 1),
            if (book.status != BookStatus.finished)
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('Mark as finished'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await service.setFinished(book, true);
                  if (mounted) setState(() {});
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.remove_done),
                title: const Text('Mark as not finished'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await service.setFinished(book, false);
                  if (mounted) setState(() {});
                },
              ),
            if (book.status != BookStatus.newBook)
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('Reset progress'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmReset(book);
                },
              ),
            if (book.isReadAlong &&
                PlaybackService.instance.book?.id != book.id)
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('Free up space'),
                subtitle: const Text(
                    'Delete the audio copied out of the EPUB. '
                    'It is copied again next time you open the book.'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await ReadAlong.clearCache(book.epubPath!);
                  book.files = [];
                  book.readAlong = null;
                  if (mounted) setState(() {});
                  _showMessage('Space freed');
                },
              ),
            if (hasEbook)
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Remove attached ebook'),
                subtitle: const Text('Deletes the ebook copy and its sync data'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await LiveSync.removeEbook(book);
                  _showMessage('Ebook removed');
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Details'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showDetails(book);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReset(Book book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset progress?'),
        content: Text('"${book.title}" will start from the beginning. '
            'Bookmarks are kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await PlaybackService.instance.resetProgress(book);
    if (mounted) setState(() {});
  }

  void _showDetails(Book book) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(book.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detail('Folder', book.folderPath),
              _detail('Files', '${book.files.length}'),
              _detail('Current file', '${book.currentFileIndex + 1}'),
              _detail('Speed', '${book.speed}x'),
              if (book.lastPlayed != null)
                _detail('Last played', book.lastPlayed!.toString().split('.').first),
              if (book.finishedAt != null)
                _detail('Finished', book.finishedAt!.toString().split('.').first),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            SelectableText(value),
          ],
        ),
      );

  Widget _bookList(List<Book> books) {
    if (books.isEmpty) {
      return const Center(child: Text('No books here yet'));
    }
    return RefreshIndicator(
      onRefresh: _scan,
      child: ListView.separated(
        itemCount: books.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 136),
        itemBuilder: (context, i) => BookTile(
          book: books[i],
          onTap: () => _openBook(books[i]),
          onLongPress: () => _showBookMenu(books[i]),
        ),
      ),
    );
  }
}
