import 'package:flutter/material.dart';

class ResponsiveText {
  ResponsiveText(String s, {required Function(dynamic context) styleBuilder, required int maxLines, required TextAlign textAlign});

  static double _getScaleFactor(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) return 0.85;      // Small phones
    if (width < 400) return 0.9;       // Standard phones
    if (width < 600) return 1.0;       // Large phones
    if (width < 900) return 1.1;       // Tablets
    return 1.2;                        // Large screens
  }

  static TextStyle heading1(BuildContext context) {
    final scale = _getScaleFactor(context);
    return TextStyle(
      fontSize: 28 * scale,
      fontWeight: FontWeight.w700,
      fontFamily: 'Rajdhani',
      letterSpacing: -0.5,
      height: 1.2,
    );
  }

  static TextStyle heading2(BuildContext context) {
    final scale = _getScaleFactor(context);
    return TextStyle(
      fontSize: 24 * scale,
      fontWeight: FontWeight.w600,
      fontFamily: 'Rajdhani',
      letterSpacing: -0.3,
      height: 1.3,
    );
  }

  static TextStyle heading3(BuildContext context) {
    final scale = _getScaleFactor(context);
    return TextStyle(
      fontSize: 20 * scale,
      fontWeight: FontWeight.w600,
      fontFamily: 'Rajdhani',
      letterSpacing: -0.2,
      height: 1.4,
    );
  }

  static TextStyle bodyLarge(BuildContext context) {
    final scale = _getScaleFactor(context);
    return TextStyle(
      fontSize: 16 * scale,
      fontWeight: FontWeight.w500,
      fontFamily: 'Inter',
      letterSpacing: 0.1,
      height: 1.5,
    );
  }

  static TextStyle bodyMedium(BuildContext context) {
    final scale = _getScaleFactor(context);
    return TextStyle(
      fontSize: 14 * scale,
      fontWeight: FontWeight.w400,
      fontFamily: 'Inter',
      letterSpacing: 0.1,
      height: 1.5,
    );
  }

  static TextStyle bodySmall(BuildContext context) {
    final scale = _getScaleFactor(context);
    return TextStyle(
      fontSize: 12 * scale,
      fontWeight: FontWeight.w400,
      fontFamily: 'Inter',
      letterSpacing: 0.2,
      height: 1.4,
    );
  }

  static TextStyle caption(BuildContext context) {
    final scale = _getScaleFactor(context);
    return TextStyle(
      fontSize: 11 * scale,
      fontWeight: FontWeight.w400,
      fontFamily: 'Inter',
      letterSpacing: 0.3,
      height: 1.3,
    );
  }

  static TextStyle button(BuildContext context) {
    final scale = _getScaleFactor(context);
    return TextStyle(
      fontSize: 14 * scale,
      fontWeight: FontWeight.w600,
      fontFamily: 'Rajdhani',
      letterSpacing: 0.5,
      height: 1.2,
    );
  }

  static TextStyle emergency(BuildContext context) {
    final scale = _getScaleFactor(context);
    return TextStyle(
      fontSize: 18 * scale,
      fontWeight: FontWeight.w700,
      fontFamily: 'Rajdhani',
      letterSpacing: 0.8,
      height: 1.1,
    );
  }

  static TextStyle monospace(BuildContext context) {
    final scale = _getScaleFactor(context);
    return TextStyle(
      fontSize: 12 * scale,
      fontWeight: FontWeight.w400,
      fontFamily: 'JetBrains Mono',
      letterSpacing: 0.0,
      height: 1.4,
    );
  }
}

class ResponsiveSpacing {
  static double xs(BuildContext context) => _getSpacing(context, 4);
  static double sm(BuildContext context) => _getSpacing(context, 8);
  static double md(BuildContext context) => _getSpacing(context, 16);
  static double lg(BuildContext context) => _getSpacing(context, 24);
  static double xl(BuildContext context) => _getSpacing(context, 32);
  static double xxl(BuildContext context) => _getSpacing(context, 48);

  static double _getSpacing(BuildContext context, double base) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) return base * 0.8;
    if (width < 600) return base;
    if (width < 900) return base * 1.2;
    return base * 1.4;
  }

  static EdgeInsets padding(BuildContext context, {
    double? all,
    double? horizontal,
    double? vertical,
    double? top,
    double? bottom,
    double? left,
    double? right,
  }) {
    final scale = ResponsiveText._getScaleFactor(context);
    
    return EdgeInsets.only(
      top: (top ?? vertical ?? all ?? 0) * scale,
      bottom: (bottom ?? vertical ?? all ?? 0) * scale,
      left: (left ?? horizontal ?? all ?? 0) * scale,
      right: (right ?? horizontal ?? all ?? 0) * scale,
    );
  }
}