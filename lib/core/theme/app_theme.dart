import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF080D19);
  static const Color surface = Color(0xFF121D31);
  static const Color surfaceRaised = Color(0xFF1A2942);
  static const Color accent = Color(0xFFFF765E);
  static const Color gold = Color(0xFFFFC45C);
  static const Color aqua = Color(0xFF5ED8D0);

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent, brightness: Brightness.dark, surface: surface,
    ).copyWith(
      primary: accent, secondary: gold, tertiary: aqua,
      surface: surface, onSurface: const Color(0xFFF4F6FC),
    );
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: background, foregroundColor: Colors.white,
        elevation: 0, centerTitle: false,
        titleTextStyle: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800),
      ),
      cardTheme: CardThemeData(
        color: surface, elevation: 5,
        shadowColor: Colors.black.withValues(alpha: .28),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: surfaceRaised,
        hintStyle: const TextStyle(color: Color(0xFF9BAAC0)),
        labelStyle: const TextStyle(color: Color(0xFFB7C4D8)),
        prefixIconColor: aqua,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceRaised, selectedColor: accent.withValues(alpha: .22),
        side: BorderSide(color: Colors.white.withValues(alpha: .08)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: const TextStyle(color: Colors.white),
      ),
      dividerTheme: DividerThemeData(color: Colors.white.withValues(alpha: .08)),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: aqua),
    );
  }
}
