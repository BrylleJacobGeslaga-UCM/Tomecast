import 'dart:io';

import 'package:flutter/services.dart';

import 'progress_store.dart';

/// Length + title tag of every file in a book. Read once with Android's
/// metadata reader, then cached in the database.
class FileInfoService {
  static const _channel = MethodChannel('tomecast/audio');

  static Future<List<FileInfo?>> get(List<String> paths) async {
    final sizes = <String, int>{};
    for (final path in paths) {
      try {
        sizes[path] = await File(path).length();
      } catch (_) {
        sizes[path] = -1;
      }
    }

    final cached = await ProgressStore.instance.getFileInfo(sizes);
    final missing = paths.where((p) => !cached.containsKey(p)).toList();

    if (missing.isNotEmpty) {
      try {
        final result = await _channel
            .invokeListMethod<Map>('fileInfo', {'paths': missing});
        for (var i = 0; i < missing.length && i < (result?.length ?? 0); i++) {
          final m = result![i];
          final info = FileInfo(
            Duration(milliseconds: (m['durationMs'] as num?)?.toInt() ?? 0),
            (m['title'] as String?)?.trim(),
          );
          cached[missing[i]] = info;
          await ProgressStore.instance
              .saveFileInfo(missing[i], sizes[missing[i]]!, info);
        }
      } catch (_) {
        // Not critical: the player just shows files instead of hours.
      }
    }
    return [for (final p in paths) cached[p]];
  }
}
