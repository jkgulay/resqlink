import 'package:flutter/material.dart';

class AppTheme {
  static final ThemeData darkTheme = ThemeData(
    fontFamily: 'Ubuntu',
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF6500),
      brightness: Brightness.dark,
      surface: const Color(0xFF0B192C),
      surfaceContainerHighest: const Color(0xFF1E3E62),
    ).copyWith(
      primary: const Color(0xFFFF6500),
      onPrimary: Colors.white,
      onSurface: Colors.white,
      onSecondary: Colors.white,
    ),
    scaffoldBackgroundColor: Colors.black,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0B192C),
      foregroundColor: Colors.white,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFFF6500),
        foregroundColor: Colors.white,
      ),
    ),
    iconTheme: const IconThemeData(color: Colors.white),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Colors.white),
    ),
  );
}