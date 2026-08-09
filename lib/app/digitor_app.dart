import 'package:flutter/material.dart';

import '../features/editor/presentation/editor_screen.dart';

class DigitorApp extends StatelessWidget {
  const DigitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Digitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const EditorScreen(),
    );
  }
}
