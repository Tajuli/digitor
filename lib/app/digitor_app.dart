import 'package:flutter/material.dart';

import '../features/editor/editor_screen.dart';

class DigitorApp extends StatelessWidget {
  const DigitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Digitor',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: Colors.blueGrey,
        scaffoldBackgroundColor: const Color(0xFF101214),
      ),
      home: const EditorScreen(),
    );
  }
}
