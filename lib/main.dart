import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'theme/tome_theme.dart';
import 'services/app_settings.dart';
import 'services/audio_handler.dart';
import 'services/playback_service.dart';
import 'services/widget_updater.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();

  // Tells Android this app plays spoken audio: it pauses for calls and
  // when headphones are unplugged, and pauses (instead of ducking) for
  // navigation voices so you don't miss words.
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.speech());

  // Starts the background service behind the notification / lock screen.
  await AudioService.init(
    builder: () => TomecastAudioHandler(PlaybackService.instance),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.brylle.tomecast.playback',
      androidNotificationChannelName: 'Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      // White status-bar icon (the colorful app icon can't be used there).
      androidNotificationIcon: 'drawable/ic_stat_tomecast',
    ),
  );

  WidgetUpdater.start(); // home screen widget

  runApp(const TomecastApp());
}

class TomecastApp extends StatelessWidget {
  const TomecastApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds with the new look when you change it in Settings.
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) => MaterialApp(
        title: 'Tomecast',
        debugShowCheckedModeBanner: false,
        theme: buildTomeTheme(AppSettings.instance.style),
        home: const SplashScreen(),
      ),
    );
  }
}
