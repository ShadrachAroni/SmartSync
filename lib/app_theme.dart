import 'package:flutter/material.dart';

class AppTheme {
  // Colors
  static const Color primary = Color(0xFF4B5FFF); // deep indigo-blue
  static const Color accent = Color(0xFF00E5C5); // teal-cyan accent

  // Light theme (kept for compatibility)
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF5F7FF),
    primaryColor: primary,
    colorScheme: ColorScheme.fromSeed(
        seedColor: primary, brightness: Brightness.light, secondary: accent),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: Colors.black87,
    ),
    textTheme: const TextTheme(
      displaySmall: TextStyle(
          fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
      headlineSmall: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87),
      bodyMedium: TextStyle(fontSize: 14, color: Colors.black87),
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 6,
      color: Colors.white,
      shadowColor: primary.withOpacity(0.15),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
        shadowColor: accent.withOpacity(0.2),
      ),
    ),
  );

  // Dark (vibrant) theme
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0E0F12),
    primaryColor: primary,
    colorScheme: ColorScheme.fromSeed(
        seedColor: primary, brightness: Brightness.dark, secondary: accent),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: Colors.white,
    ),
    textTheme: const TextTheme(
      displaySmall: TextStyle(
          fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
      headlineSmall: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white70),
      bodyMedium: TextStyle(fontSize: 14, color: Colors.white70),
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 6,
      color: const Color(0xFF171717),
      shadowColor: primary.withOpacity(0.3),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
        shadowColor: accent.withOpacity(0.3),
      ),
    ),
  );
}
