import 'package:flutter/material.dart';

/// Offline-safe font helper that uses bundled fonts
/// Since Poppins is not bundled, we use Inter as a substitute
class OfflineFonts {
  /// Get Poppins-style font (uses bundled Inter font as substitute)
  static TextStyle poppins({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
    Color? decorationColor,
  }) {
    // Use bundled Inter font as Poppins substitute (both are geometric sans-serif fonts)
    return TextStyle(
      fontFamily: 'Inter',
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      decoration: decoration,
      decorationColor: decorationColor,
    );
  }

  /// Get Ubuntu font (already bundled)
  static TextStyle ubuntu({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) {
    return TextStyle(
      fontFamily: 'Ubuntu',
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      decoration: decoration,
    );
  }

  /// Get Inter font (already bundled)
  static TextStyle inter({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) {
    return TextStyle(
      fontFamily: 'Inter',
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      decoration: decoration,
    );
  }

  /// Get JetBrains Mono font (already bundled)
  static TextStyle jetBrainsMono({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) {
    return TextStyle(
      fontFamily: 'JetBrains Mono',
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      decoration: decoration,
    );
  }

  /// Get Rajdhani font (already bundled)
  static TextStyle rajdhani({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
    List<Shadow>? shadows,
  }) {
    return TextStyle(
      fontFamily: 'Rajdhani',
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      decoration: decoration,
      shadows: shadows,
    );
  }
}
