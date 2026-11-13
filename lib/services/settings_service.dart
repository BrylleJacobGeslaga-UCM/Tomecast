import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _rootFolderKey = 'root_folder';

  Future<String?> getRootFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rootFolderKey);
  }

  Future<void> setRootFolder(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rootFolderKey, path);
  }
}
