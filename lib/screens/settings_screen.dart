import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/folder_access.dart';
import '../services/playback_service.dart';
import '../theme/tome_theme.dart';
import '../utils/format.dart';

/// Returns true (via Navigator.pop) if the audiobook folder was changed,
/// so the library knows to rescan.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _s = AppSettings.instance;
  bool _folderChanged = false;

  Future<void> _changeFolder() async {
    try {
      final path = await FolderAccess.pickFolder();
      if (path == null) return;
      await _s.setRootFolder(path);
      setState(() => _folderChanged = true);
    } on FolderAccessException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _pickSeconds({
    required String title,
    required List<int> options,
    required int current,
    required void Function(int) onPicked,
  }) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          for (final o in options)
            ListTile(
              title: Text(formatSkip(Duration(seconds: o))),
              trailing: o == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, o),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => onPicked(picked));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _folderChanged);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(
          children: [
            _header('Appearance'),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Theme'),
              subtitle: Text(_s.style.label),
              onTap: _pickStyle,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.shelves),
              title: const Text('Bookshelf view'),
              subtitle: const Text('Show books as covers on shelves (off = list)'),
              value: _s.shelfLayout,
              onChanged: (v) => setState(() => _s.shelfLayout = v),
            ),

            _header('Library'),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Audiobook folder'),
              subtitle: Text(_s.rootFolder ?? 'Not set'),
              onTap: _changeFolder,
            ),

            _header('Playback'),
            SwitchListTile(
              secondary: const Icon(Icons.history),
              title: const Text('Smart rewind'),
              subtitle: const Text(
                  'Go back a few seconds when you resume after a pause'),
              value: _s.smartRewind,
              onChanged: (v) => setState(() => _s.smartRewind = v),
            ),
            ListTile(
              leading: const Icon(Icons.replay_10),
              title: const Text('Short skip'),
              subtitle: Text(formatSkip(Duration(seconds: _s.shortSkipSeconds))),
              onTap: () => _pickSeconds(
                title: 'Short skip',
                options: const [5, 10, 15, 20, 30],
                current: _s.shortSkipSeconds,
                onPicked: (v) => _s.shortSkipSeconds = v,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.fast_forward),
              title: const Text('Long skip'),
              subtitle: Text(formatSkip(Duration(seconds: _s.longSkipSeconds))),
              onTap: () => _pickSeconds(
                title: 'Long skip',
                options: const [30, 60, 120, 300],
                current: _s.longSkipSeconds,
                onPicked: (v) => _s.longSkipSeconds = v,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.headphones),
              title: const Text('Headset next / previous'),
              subtitle: Text(_s.headsetAction == HeadsetAction.skip30
                  ? 'Skip 30 seconds'
                  : 'Next / previous chapter or file'),
              onTap: () async {
                final picked = await showDialog<HeadsetAction>(
                  context: context,
                  builder: (context) => SimpleDialog(
                    title: const Text('Headset next / previous'),
                    children: [
                      for (final a in HeadsetAction.values)
                        ListTile(
                          title: Text(a == HeadsetAction.skip30
                              ? 'Skip 30 seconds'
                              : 'Next / previous chapter or file'),
                          trailing: a == _s.headsetAction
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.pop(context, a),
                        ),
                    ],
                  ),
                );
                if (picked != null) setState(() => _s.headsetAction = picked);
              },
            ),

            SwitchListTile(
              secondary: const Icon(Icons.screen_rotation_alt),
              title: const Text('Flip to pause'),
              subtitle: const Text(
                  'Turn the phone face down to pause, face up to resume'),
              value: _s.flipToPause,
              onChanged: (v) {
                setState(() => _s.flipToPause = v);
                PlaybackService.instance.updateFlipListener();
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.queue_play_next),
              title: const Text('Play next book automatically'),
              subtitle: const Text(
                  'When a book ends, start the next unfinished one'),
              value: _s.autoNextBook,
              onChanged: (v) => setState(() => _s.autoNextBook = v),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.title),
              title: const Text('Show title tags'),
              subtitle: const Text(
                  'Use the title stored in each file (ID3) instead of the file name'),
              value: _s.useTagTitles,
              onChanged: (v) => setState(() => _s.useTagTitles = v),
            ),

            _header('Sleep timer'),
            SwitchListTile(
              secondary: const Icon(Icons.vibration),
              title: const Text('Shake to reset'),
              subtitle: const Text(
                  'Shake the phone to restart the timer, or to keep '
                  'listening right after it stops'),
              value: _s.shakeToExtend,
              onChanged: (v) => setState(() => _s.shakeToExtend = v),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.volume_down),
              title: const Text('Fade out'),
              subtitle: const Text('Lower the volume in the last 10 seconds'),
              value: _s.sleepFadeOut,
              onChanged: (v) => setState(() => _s.sleepFadeOut = v),
            ),

            _header('About'),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Tomecast'),
              subtitle: Text('Free audiobook player'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickStyle() async {
    final picked = await showDialog<TomeStyle>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Theme'),
        children: [
          for (final style in TomeStyle.values)
            ListTile(
              leading: _Swatch(TomePalette.of(style)),
              title: Text(style.label),
              subtitle: Text(style.description),
              trailing: style == _s.style ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, style),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => _s.style = picked);
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );
}

/// Little preview circle of a theme: background, trim ring, glow dot.
class _Swatch extends StatelessWidget {
  final TomePalette p;

  const _Swatch(this.p);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [p.bgTop, p.bgBottom]),
        border: Border.all(color: p.trim, width: 2.5),
      ),
      child: Center(
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.glow,
            boxShadow: [BoxShadow(color: p.glow, blurRadius: 8)],
          ),
        ),
      ),
    );
  }
}
