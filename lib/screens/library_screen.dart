import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/book.dart';
import '../services/library_scanner.dart';
import '../services/progress_store.dart';
import '../services/settings_service.dart';
import '../widgets/book_tile.dart';
import 'player_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _settings = SettingsService();
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
    _rootFolder = await _settings.getRootFolder();
    if (_rootFolder != null && await _ensurePermission()) {
      await _scan();
    } else {
      setState(() => _loading = false);
    }
  }

  /// Android 11+ needs "All files access" to read audio files by path.
  /// Fine for a personal app you install from GitHub (not for Play Store).
  Future<bool> _ensurePermission() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.manageExternalStorage.request().isGranted) return true;
    // Older Android versions (10 and below)
    return await Permission.storage.request().isGranted;
  }

  Future<void> _pickRootFolder() async {
    if (!await _ensurePermission()) {
      _showMessage('Storage permission is needed to read your audiobooks.');
      return;
    }
    // file_picker v12+ uses static methods (no ".platform").
    final picked = await FilePicker.getDirectoryPath();
    if (picked == null) return;

    final path = _toFilePath(picked);
    if (path == null) {
      _showMessage('Could not open that folder. Try a folder on internal storage.');
      return;
    }

    await _settings.setRootFolder(path);
    _rootFolder = path;
    await _scan();
  }

  Future<void> _scan() async {
    if (_rootFolder == null) return;
    setState(() => _loading = true);
    final books = await _scanner.scan(_rootFolder!);
    final progress = await ProgressStore.instance.getAll();
    for (final book in books) {
      book.applyProgress(progress[book.id]);
    }
    if (!mounted) return;
    setState(() {
      _books = books;
      _loading = false;
    });
  }

  /// Newer Android pickers may return a "content://" address instead of a
  /// normal path. For internal storage we can turn it back into a path:
  /// content://.../tree/primary%3AAudiobooks%2FWarcraft
  ///   → /storage/emulated/0/Audiobooks/Warcraft
  String? _toFilePath(String picked) {
    if (picked.startsWith('/')) return picked;
    if (!picked.startsWith('content://')) return null;

    final decoded = Uri.decodeComponent(picked);
    final match = RegExp(r'/tree/primary:(.*)$').firstMatch(decoded);
    if (match == null) return null; // SD card / cloud folders: handled with SAF later
    final relative = match.group(1)!.split('/document/').first;
    return '/storage/emulated/0/$relative';
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
              tooltip: 'Change folder',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: _pickRootFolder,
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
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerScreen(book: book)),
    );
    // The player updates the Book object directly, so just redraw.
    if (mounted) setState(() {});
  }

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
        ),
      ),
    );
  }
}
