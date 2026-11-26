import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFF090D16),
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF2878F0),
      brightness: Brightness.dark,
      surface: const Color(0xFF111827),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF090D16),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: Color(0xFF151E2E),
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF151E2E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
