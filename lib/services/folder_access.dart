import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// Storage permission + choosing the audiobooks folder.
/// Used by the library (first run) and the settings screen.
class FolderAccess {
  /// Android 11+ needs "All files access" to read audio files by path.
  /// Fine for a personal app you install from GitHub (not for Play Store).
  static Future<bool> ensurePermission() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.manageExternalStorage.request().isGranted) return true;
    // Older Android versions (10 and below)
    return await Permission.storage.request().isGranted;
  }

  /// Returns the chosen folder path, or null if cancelled.
  /// Throws [FolderAccessException] with a message to show the user.
  static Future<String?> pickFolder() async {
    if (!await ensurePermission()) {
      throw FolderAccessException(
          'Storage permission is needed to read your audiobooks.');
    }
    // file_picker v12+ uses static methods (no ".platform").
    final picked = await FilePicker.getDirectoryPath();
    if (picked == null) return null;

    final path = _toFilePath(picked);
    if (path == null) {
      throw FolderAccessException(
          'Could not open that folder. Try a folder on internal storage.');
    }
    return path;
  }

  /// Newer Android pickers may return a "content://" address instead of a
  /// normal path. For internal storage we can turn it back into a path:
  /// content://.../tree/primary%3AAudiobooks%2FWarcraft
  ///   → /storage/emulated/0/Audiobooks/Warcraft
  static String? _toFilePath(String picked) {
    if (picked.startsWith('/')) return picked;
    if (!picked.startsWith('content://')) return null;

    final decoded = Uri.decodeComponent(picked);
    final match = RegExp(r'/tree/primary:(.*)$').firstMatch(decoded);
    if (match == null) return null; // SD card / cloud: handled with SAF later
    final relative = match.group(1)!.split('/document/').first;
    return '/storage/emulated/0/$relative';
  }
}

class FolderAccessException implements Exception {
  final String message;
  FolderAccessException(this.message);
}
