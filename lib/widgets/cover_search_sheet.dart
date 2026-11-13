import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';

/// Finds covers on Open Library (free, no account) and saves the chosen one
/// as cover.jpg in the book's folder. Returns true (via pop) if saved.
class CoverSearchSheet extends StatefulWidget {
  final Book book;

  const CoverSearchSheet({super.key, required this.book});

  @override
  State<CoverSearchSheet> createState() => _CoverSearchSheetState();
}

class _CoverSearchSheetState extends State<CoverSearchSheet> {
  late final _query = TextEditingController(text: _cleanTitle(widget.book.title));
  List<int>? _coverIds; // Open Library cover ids
  bool _loading = false;
  bool _saving = false;
  String? _error;

  /// "5. Day of the Dragon" → "Day of the Dragon"
  static String _cleanTitle(String title) => title
      .replaceFirst(RegExp(r'^\s*\d+\s*[\.\-_)]?\s*'), '')
      .replaceAll(RegExp(r'[_\[\]()]'), ' ')
      .trim();

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<String> _get(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'Tomecast (audiobook player)');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final body = await _get(Uri.https('openlibrary.org', '/search.json', {
        'q': q,
        'fields': 'cover_i',
        'limit': '40',
      }));
      final docs = (jsonDecode(body)['docs'] as List?) ?? [];
      final ids = <int>{
        for (final d in docs)
          if (d['cover_i'] is int) d['cover_i'] as int,
      }.toList();
      setState(() => _coverIds = ids);
    } catch (e) {
      setState(() => _error = 'Search failed. Check your internet connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick(int id) async {
    setState(() => _saving = true);
    final client = HttpClient();
    try {
      final request = await client.getUrl(
          Uri.https('covers.openlibrary.org', '/b/id/$id-L.jpg'));
      final response = await request.close();
      if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');

      final target = File(p.join(widget.book.folderPath, 'cover.jpg'));
      final tmp = File('${target.path}.part');
      await response.pipe(tmp.openWrite());
      await tmp.rename(target.path);

      // Forget the old picture so the new one shows right away.
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = 'Could not save the cover: $e');
    } finally {
      client.close();
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = _coverIds;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: 'Search covers (title, author)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: _loading || _saving
                ? const Center(child: CircularProgressIndicator())
                : ids == null
                    ? const SizedBox.shrink()
                    : ids.isEmpty
                        ? const Center(child: Text('No covers found. Try another search.'))
                        : GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 0.66,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                            itemCount: ids.length,
                            itemBuilder: (context, i) => InkWell(
                              onTap: () => _pick(ids[i]),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  'https://covers.openlibrary.org/b/id/${ids[i]}-M.jpg',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.broken_image),
                                ),
                              ),
                            ),
                          ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Covers from Open Library',
                style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
