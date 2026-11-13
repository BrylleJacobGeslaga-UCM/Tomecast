import 'package:flutter/material.dart';

import 'screens/library_screen.dart';

void main() {
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
