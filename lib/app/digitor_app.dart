import 'package:digitor/features/home/presentation/home_page.dart';
import 'package:flutter/material.dart';

class DigitorApp extends StatelessWidget {
  const DigitorApp({super.key});

  static const Color _backgroundColor = Color(0xFF0F1012);
  static const Color _seedColor = Color(0xFF8B5CF6);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
      surface: _backgroundColor,
    );

    return MaterialApp(
      title: 'Digitor',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: _backgroundColor,
        fontFamily: 'Roboto',
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.w800,
            letterSpacing: 4,
            height: 1.05,
          ),
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}
