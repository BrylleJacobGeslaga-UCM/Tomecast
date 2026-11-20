import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:permission_handler/permission_handler.dart';

import '../models/book.dart';
import '../services/app_settings.dart';
import '../services/folder_access.dart';
import '../services/library_scanner.dart';
import '../services/live_sync.dart';
import '../services/playback_service.dart';
import '../services/progress_store.dart';
import '../services/read_along.dart';
import '../utils/book_sort.dart';
import '../theme/ornaments.dart';
import '../theme/tome_theme.dart';
import '../widgets/book_tile.dart';
import '../widgets/bookshelf.dart';
import '../widgets/cover_search_sheet.dart';
import '../widgets/library_extras.dart';
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

  // Collections (chips above the shelves)
  List<BookCollection> _collections = [];

  // Search
  bool _searching = false;
  String _query = '';
  final _searchController = TextEditingController();
  List<Book> _books = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Android 13+: needed for the playback notification / lock-screen controls.
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
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
      if (i != -1) {
        playing.coverPath = books[i].coverPath; // picks up a new cover
        books[i] = playing;
      }
    }
    // Read-along books already prepared this session stay ready.
    for (var i = 0; i < books.length; i++) {
      final old = _books.where((b) => b.id == books[i].id && b.isReady);
      if (books[i].isReadAlong && !books[i].isReady && old.isNotEmpty) {
        old.first.coverPath = books[i].coverPath;
        books[i] = old.first;
      }
    }
    await _loadLibraryInfo(books);
    PlaybackService.instance.library = books; // for "play next book"
    if (!mounted) return;
    setState(() {
      _books = books;
      _loading = false;
    });
  }

  /// Rating, date added, collections and known length for every book.
  Future<void> _loadLibraryInfo(List<Book> books) async {
    final store = ProgressStore.instance;
    await store.ensureAdded(books.map((b) => b.id));
    final meta = await store.getBookMeta();
    final memberships = await store.getMemberships();
    final durations =
        await store.getKnownDurations([for (final b in books) ...b.files]);
    _collections = await store.getCollections();
    // A remembered collection that was deleted: back to all books.
    final selected = AppSettings.instance.selectedCollection;
    if (selected != null && !_collections.any((c) => c.id == selected)) {
      AppSettings.instance.selectedCollection = null;
    }

    for (final b in books) {
      final m = meta[b.id];
      b.rating = m?.rating ?? 0;
      b.review = m?.review ?? '';
      b.addedAt = m?.addedAt;
      b.collectionIds = memberships[b.id] ?? {};
      final lengths = [for (final f in b.files) durations[f]];
      b.knownLength = lengths.isNotEmpty && lengths.every((d) => d != null && d > Duration.zero)
          ? lengths.fold<Duration>(Duration.zero, (a, d) => a + d!)
          : null;
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Back button closes the search first.
    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _searching) _closeSearch();
      },
      child: TomeBackground(
      child: DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: _searching ? _searchField() : const Text('LIBRARY'),
          centerTitle: false,
          actions: _searching
              ? [
                  IconButton(
                    tooltip: 'Close search',
                    icon: const Icon(Icons.close),
                    onPressed: _closeSearch,
                  ),
                ]
              : [
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search),
              onPressed: _rootFolder == null
                  ? null
                  : () => setState(() => _searching = true),
            ),
            IconButton(
              tooltip: 'Sort',
              icon: const Icon(Icons.sort),
              onPressed: _rootFolder == null ? null : _showSortSheet,
            ),
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

    final selected = AppSettings.instance.selectedCollection;
    return Column(
      children: [
        CollectionChips(
          collections: _collections,
          selected: selected,
          onSelected: (id) => setState(() => AppSettings.instance.selectedCollection = id),
          onCreate: _createCollection,
          onEdit: _editCollection,
        ),
        Expanded(
          child: TabBarView(
            children: [
              _bookList(_visible(_books),
                  header: _query.isEmpty && selected == null ? _continueCard() : null),
              _bookList(_visible(
                  _books.where((b) => b.status == BookStatus.newBook).toList())),
              _bookList(_visible(_startedBooks())),
              _bookList(_visible(
                  _books.where((b) => b.status == BookStatus.finished).toList())),
            ],
          ),
        ),
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
      // Can be taller than the default half screen, and scrolls if needed
      // (long menus, big font sizes).
      isScrollControlled: true,
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
         child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(book.title,
                  style: Theme.of(sheetContext).textTheme.titleMedium),
              subtitle: Text(book.files.length == 1
                  ? '1 file'
                  : '${book.files.length} files'),
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
              leading: const Icon(Icons.star_outline),
              title: Text(book.rating == 0 ? 'Rate' : 'Rating: ${'★' * book.rating}'),
              onTap: () {
                Navigator.pop(sheetContext);
                _rate(book);
              },
            ),
            ListTile(
              leading: const Icon(Icons.collections_bookmark_outlined),
              title: const Text('Collections'),
              subtitle: book.collectionIds.isEmpty
                  ? null
                  : Text(_collections
                      .where((c) => book.collectionIds.contains(c.id))
                      .map((c) => c.name)
                      .join(', ')),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickCollections(book);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_search),
              title: const Text('Find cover online'),
              onTap: () {
                Navigator.pop(sheetContext);
                _findCover(book);
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
      ),
    );
  }

  Future<void> _findCover(Book book) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: CoverSearchSheet(book: book),
      ),
    );
    if (saved == true) {
      // A cover.jpg now exists: rescan so every screen uses it.
      await _scan();
      _showMessage('Cover saved to ${p.basename(book.folderPath)}/cover.jpg');
    }
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

  // ---------------- Search ----------------

  Widget _searchField() {
    final p = context.tome;
    return TextField(
      controller: _searchController,
      autofocus: true,
      style: TextStyle(color: p.text, fontSize: 18),
      cursorColor: p.glow,
      decoration: InputDecoration(
        hintText: 'Search your tomes…',
        hintStyle: TextStyle(color: p.textMuted),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
      onChanged: (v) => setState(() => _query = v.trim()),
    );
  }

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _searching = false;
      _query = '';
    });
  }

  /// Search → collection → sort, applied to every tab.
  List<Book> _visible(List<Book> books) {
    var list = _filter(books);
    final collection = AppSettings.instance.selectedCollection;
    if (collection != null) {
      list = list.where((b) => b.collectionIds.contains(collection)).toList();
    }
    final s = AppSettings.instance;
    return sortBooks(list, s.sortBy, ascending: s.sortAscending);
  }

  // ---------------- Sort ----------------

  Future<void> _showSortSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85),
      builder: (_) => const SortSheet(),
    );
    if (mounted) setState(() {});
  }

  // ---------------- Collections ----------------

  Future<void> _createCollection({Book? addBook}) async {
    final name = await askName(context, title: 'New collection');
    if (name == null) return;
    final id = await ProgressStore.instance.createCollection(name);
    if (addBook != null) {
      await ProgressStore.instance.setInCollection(id, addBook.id, true);
      addBook.collectionIds.add(id);
    }
    _collections = await ProgressStore.instance.getCollections();
    if (mounted) setState(() {});
  }

  Future<void> _editCollection(BookCollection c) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(c.name, style: Theme.of(sheet).textTheme.titleMedium)),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Rename'),
            onTap: () => Navigator.pop(sheet, 'rename'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete collection'),
            subtitle: const Text('The books themselves are not deleted'),
            onTap: () => Navigator.pop(sheet, 'delete'),
          ),
        ]),
      ),
    );
    if (action == 'rename') {
      final name = await askName(context, title: 'Rename collection', initial: c.name);
      if (name == null) return;
      await ProgressStore.instance.renameCollection(c.id, name);
    } else if (action == 'delete') {
      await ProgressStore.instance.deleteCollection(c.id);
      for (final b in _books) {
        b.collectionIds.remove(c.id);
      }
      if (AppSettings.instance.selectedCollection == c.id) {
        AppSettings.instance.selectedCollection = null;
      }
    } else {
      return;
    }
    _collections = await ProgressStore.instance.getCollections();
    if (mounted) setState(() {});
  }

  Future<void> _pickCollections(Book book) async {
    await showModalBottomSheet(
      context: context,
      builder: (_) => BookCollectionsSheet(
        book: book,
        collections: _collections,
        onCreate: () => _createCollection(addBook: book),
      ),
    );
    _collections = await ProgressStore.instance.getCollections();
    if (mounted) setState(() {});
  }

  Future<void> _rate(Book book) async {
    final changed = await showRatingDialog(context, book);
    if (changed && mounted) setState(() {});
  }

  /// Books whose title contains every word typed (any order, any case).
  /// "dragon day" finds "5. Day of the Dragon".
  List<Book> _filter(List<Book> books) {
    if (_query.isEmpty) return books;
    final words = _query.toLowerCase().split(RegExp(r'\s+'));
    return books.where((b) {
      final title = b.title.toLowerCase();
      return words.every(title.contains);
    }).toList();
  }

  /// Most recently played unfinished book, shown above the shelves.
  Widget? _continueCard() {
    final started = _startedBooks();
    if (started.isEmpty) return null;
    return ContinueCard(book: started.first, onTap: () => _openBook(started.first));
  }

  Widget _bookList(List<Book> books, {Widget? header}) {
    if (books.isEmpty) {
      return Center(
        child: Text(_query.isEmpty
            ? 'No books here yet'
            : 'No books match "$_query"'),
      );
    }
    if (AppSettings.instance.shelfLayout) {
      return RefreshIndicator(
        onRefresh: _scan,
        child: Bookshelf(
          books: books,
          header: header,
          onTap: _openBook,
          onLongPress: _showBookMenu,
        ),
      );
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
