import 'package:flutter/material.dart';

import '../core/engine/bootstrapped_engine_gateway.dart';
import '../core/engine/engine_gateway.dart';
import '../features/editor/presentation/editor_screen.dart';
import '../features/editor/presentation/mobile_editor_screen.dart';

class DigitorApp extends StatefulWidget {
  const DigitorApp({super.key});

  @override
  State<DigitorApp> createState() => _DigitorAppState();
}

class _DigitorAppState extends State<DigitorApp> {
  late final EngineGateway _engine = BootstrappedDigitorEngineGateway();

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
      home: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 760) {
            return MobileEditorScreen(engine: _engine);
          }
          return EditorScreen(engine: _engine);
        },
      ),
    );
  }
}
