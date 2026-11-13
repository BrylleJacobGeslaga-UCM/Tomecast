import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What headset / earbud next & previous buttons do.
enum HeadsetAction { skip30, chapterOrFile }

/// All user settings, saved on the phone. Loaded once in main().
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final instance = AppSettings._();

  late SharedPreferences _prefs;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ---- Library ----
  String? get rootFolder => _prefs.getString('root_folder');
  Future<void> setRootFolder(String path) async {
    await _prefs.setString('root_folder', path);
    notifyListeners();
  }

  // ---- Playback ----
  bool get smartRewind => _prefs.getBool('smart_rewind') ?? true;
  set smartRewind(bool v) => _set(() => _prefs.setBool('smart_rewind', v));

  /// The small skip buttons (default 10 s).
  int get shortSkipSeconds => _prefs.getInt('short_skip') ?? 10;
  set shortSkipSeconds(int v) => _set(() => _prefs.setInt('short_skip', v));

  /// The big skip buttons (default 1 min).
  int get longSkipSeconds => _prefs.getInt('long_skip') ?? 60;
  set longSkipSeconds(int v) => _set(() => _prefs.setInt('long_skip', v));

  HeadsetAction get headsetAction =>
      HeadsetAction.values[(_prefs.getInt('headset_action') ?? 0)
          .clamp(0, HeadsetAction.values.length - 1)];
  set headsetAction(HeadsetAction v) =>
      _set(() => _prefs.setInt('headset_action', v.index));

  // ---- Sleep timer ----
  bool get shakeToExtend => _prefs.getBool('shake_to_extend') ?? true;
  set shakeToExtend(bool v) => _set(() => _prefs.setBool('shake_to_extend', v));

  bool get sleepFadeOut => _prefs.getBool('sleep_fade') ?? true;
  set sleepFadeOut(bool v) => _set(() => _prefs.setBool('sleep_fade', v));

  void _set(Future<bool> Function() write) {
    write();
    notifyListeners();
  }
}
