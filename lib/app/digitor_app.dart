import 'package:flutter/material.dart';

import '../core/engine/engine_gateway.dart';
import '../core/engine/ffi_engine_gateway.dart';
import '../features/editor/presentation/editor_screen.dart';

class DigitorApp extends StatefulWidget {
  const DigitorApp({super.key});

  @override
  State<DigitorApp> createState() => _DigitorAppState();
}

class _DigitorAppState extends State<DigitorApp> {
  late final EngineGateway _engine = DigitorFfiEngineGateway();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Digitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF121212),
        dividerTheme: const DividerThemeData(space: 1, thickness: 1),
        visualDensity: VisualDensity.compact,
      ),
      home: EditorScreen(engine: _engine),
    );
  }
}
