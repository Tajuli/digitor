import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/engine/bootstrapped_engine_gateway.dart';
import '../core/engine/engine_gateway.dart';
import '../features/editor/presentation/editor_screen.dart';
import '../features/editor/presentation/mobile_editor_screen.dart';
import 'export_progress_overlay.dart';

enum EditorSurfaceFamily { mobile, desktop }

/// Product UI contract:
/// - Android and iOS always share the mobile editor surface.
/// - Windows and macOS always share the desktop editor surface.
///
/// Window width may change density inside a surface, but it must never switch a
/// target platform into the other product UI family.
EditorSurfaceFamily editorSurfaceFamilyFor(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return EditorSurfaceFamily.mobile;
    case TargetPlatform.windows:
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return EditorSurfaceFamily.desktop;
  }
}

class DigitorApp extends StatefulWidget {
  const DigitorApp({super.key});

  @override
  State<DigitorApp> createState() => _DigitorAppState();
}

class _DigitorAppState extends State<DigitorApp> {
  late final EngineGateway _engine = BootstrappedDigitorEngineGateway();

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF30E0C3),
      brightness: Brightness.dark,
      surface: const Color(0xFF101014),
    );

    final editor = switch (editorSurfaceFamilyFor(defaultTargetPlatform)) {
      EditorSurfaceFamily.mobile => MobileEditorScreen(engine: _engine),
      EditorSurfaceFamily.desktop => EditorScreen(engine: _engine),
    };

    return MaterialApp(
      title: 'Digitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFF09090B),
        dividerTheme: const DividerThemeData(
          color: Color(0xFF222227),
          space: 1,
          thickness: 1,
        ),
        visualDensity: VisualDensity.compact,
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF17171C),
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF2A2A31)),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF2A2A31)),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: ExportProgressOverlay(
        engine: _engine,
        child: editor,
      ),
    );
  }
}
