import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';

import 'screens/library_screen.dart';
import 'services/app_settings.dart';
import 'services/audio_handler.dart';
import 'services/playback_service.dart';

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
    ),
  );

  runApp(const TomecastApp());
}

class TomecastApp extends StatelessWidget {
  const TomecastApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tomecast',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.lightBlue,
        scaffoldBackgroundColor: Colors.black,
      ),
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.lightBlue,
      ),
      home: const LibraryScreen(),
    );
  }
}
