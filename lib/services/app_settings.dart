import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/tome_theme.dart';

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

  // ---- Appearance ----
  TomeStyle get style => TomeStyle.values.firstWhere(
        (s) => s.name == _prefs.getString('style'),
        orElse: () => TomeStyle.arcane,
      );
  set style(TomeStyle v) => _set(() => _prefs.setString('style', v.name));

  /// Bookshelf grid (true) or list (false).
  bool get shelfLayout => _prefs.getBool('shelf_layout') ?? true;
  set shelfLayout(bool v) => _set(() => _prefs.setBool('shelf_layout', v));

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

  // ---- Sound (applies to every book) ----
  /// Volume boost in dB, 0 = off.
  int get boostDb => _prefs.getInt('boost_db') ?? 0;
  set boostDb(int v) => _set(() => _prefs.setInt('boost_db', v));

  double get pitch => _prefs.getDouble('pitch') ?? 1.0;
  set pitch(double v) => _set(() => _prefs.setDouble('pitch', v));

  bool get skipSilence => _prefs.getBool('skip_silence') ?? false;
  set skipSilence(bool v) => _set(() => _prefs.setBool('skip_silence', v));

  bool get eqEnabled => _prefs.getBool('eq_enabled') ?? false;
  set eqEnabled(bool v) => _set(() => _prefs.setBool('eq_enabled', v));

  /// Gain per equalizer band in dB.
  List<double> get eqGains => (_prefs.getStringList('eq_gains') ?? [])
      .map((g) => double.tryParse(g) ?? 0)
      .toList();
  set eqGains(List<double> v) => _set(() =>
      _prefs.setStringList('eq_gains', v.map((g) => g.toString()).toList()));

  // ---- Player ----
  /// 0 = files, 1 = hours, 2 = percent (tap the progress line to switch).
  int get positionDisplay => _prefs.getInt('position_display') ?? 0;
  set positionDisplay(int v) => _set(() => _prefs.setInt('position_display', v));

  /// Show the title tag (ID3 etc.) instead of the file name.
  bool get useTagTitles => _prefs.getBool('tag_titles') ?? false;
  set useTagTitles(bool v) => _set(() => _prefs.setBool('tag_titles', v));

  bool get flipToPause => _prefs.getBool('flip_to_pause') ?? false;
  set flipToPause(bool v) => _set(() => _prefs.setBool('flip_to_pause', v));

  bool get autoNextBook => _prefs.getBool('auto_next_book') ?? false;
  set autoNextBook(bool v) => _set(() => _prefs.setBool('auto_next_book', v));

  // ---- Per book: skip the start / end of every file ----
  Duration skipStart(String bookId) =>
      Duration(seconds: _prefs.getInt('skip_start:$bookId') ?? 0);
  Duration skipEnd(String bookId) =>
      Duration(seconds: _prefs.getInt('skip_end:$bookId') ?? 0);
  void setSkip(String bookId, Duration start, Duration end) => _set(() async {
        await _prefs.setInt('skip_start:$bookId', start.inSeconds);
        return _prefs.setInt('skip_end:$bookId', end.inSeconds);
      });

  void _set(Future<bool> Function() write) {
    write();
    notifyListeners();
  }
}
