import 'package:flutter/material.dart';
import 'package:resqlink/utils/offline_fonts.dart';

class ResponsiveText {
  static double _getScaleFactor(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) return 0.85; // Small phones
    if (width < 400) return 0.9; // Standard phones
    if (width < 600) return 1.0; // Large phones
    if (width < 900) return 1.1; // Tablets
    return 1.2; // Large screens
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

  static EdgeInsets padding(
    BuildContext context, {
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

class ResponsiveWidget extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;
  final double mobileBreakpoint;
  final double tabletBreakpoint;

  const ResponsiveWidget({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
    this.mobileBreakpoint = 600,
    this.tabletBreakpoint = 900,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= tabletBreakpoint && desktop != null) {
          return desktop!;
        } else if (constraints.maxWidth >= mobileBreakpoint && tablet != null) {
          return tablet!;
        } else {
          return mobile;
        }
      },
    );
  }
}

class ResponsiveTextWidget extends StatelessWidget {
  final String text;
  final TextStyle Function(BuildContext) styleBuilder;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const ResponsiveTextWidget(
    this.text, {
    super.key,
    required this.styleBuilder,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: styleBuilder(context),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}

class ResQLinkTheme {
  static const Color primaryRed = Color(0xFFE53935);
  static const Color darkRed = Color(0xFFB71C1C);
  static const Color emergencyOrange = Color(0xFFFF6F00);
  static const Color safeGreen = Color(0xFF43A047);
  static const Color warningYellow = Color(0xFFFFD600);
  static const Color offlineGray = Color(0xFF616161);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color cardDark = Color(0xFF2C2C2C);
  static const Color locationBlue = Color(0xFF2196F3);
  static const Color orange = Color.fromARGB(255, 255, 128, 0);
  static const Color primaryBlue = Color(0xFF2196F3);

  // Primary Colors
  static const Color primaryColor = Color(0xFF2196F3);
  static const Color secondaryColor = Color(0xFF03DAC6);
  static const Color backgroundColor = Color(0xFF121212);
  static const Color surfaceColor = Color(0xFF1E1E1E);

  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    primarySwatch: MaterialColor(0xFFE53935, {
      50: Color(0xFFFFEBEE),
      100: Color(0xFFFFCDD2),
      200: Color(0xFFEF9A9A),
      300: Color(0xFFE57373),
      400: Color(0xFFEF5350),
      500: primaryRed,
      600: Color(0xFFE53935),
      700: Color(0xFFD32F2F),
      800: Color(0xFFC62828),
      900: darkRed,
    }),
    primaryColor: primaryRed,
    scaffoldBackgroundColor: backgroundDark,
    cardColor: cardDark,
    appBarTheme: AppBarTheme(
      backgroundColor: surfaceDark,
      foregroundColor: Colors.white,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.3),
    ),
    textTheme: textTheme,
    iconTheme: IconThemeData(color: Colors.white),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryRed,
        foregroundColor: Colors.white,
        textStyle: OfflineFonts.rajdhani(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: cardDark,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.3),
    ),
  );

  static TextTheme get textTheme => TextTheme(
    // Headlines
    displayLarge: OfflineFonts.rajdhani(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      color: Colors.white,
    ),
    displayMedium: OfflineFonts.rajdhani(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      color: Colors.white,
    ),
    displaySmall: OfflineFonts.rajdhani(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: Colors.white,
    ),

    // Headlines
    headlineLarge: OfflineFonts.rajdhani(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      color: Colors.white,
    ),
    headlineMedium: OfflineFonts.rajdhani(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: Colors.white,
    ),
    headlineSmall: OfflineFonts.rajdhani(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: Colors.white,
    ),

    // Titles
    titleLarge: OfflineFonts.inter(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      color: Colors.white,
    ),
    titleMedium: OfflineFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      color: Colors.white,
    ),
    titleSmall: OfflineFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      color: Colors.white,
    ),

    // Body text
    bodyLarge: OfflineFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.1,
      color: Colors.white,
      height: 1.5,
    ),
    bodyMedium: OfflineFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.1,
      color: Colors.white,
      height: 1.5,
    ),
    bodySmall: OfflineFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
      color: Colors.white70,
      height: 1.4,
    ),

    // Labels and captions
    labelLarge: OfflineFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      color: Colors.white,
    ),
    labelMedium: OfflineFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      color: Colors.white,
    ),
    labelSmall: OfflineFonts.inter(
      fontSize: 10,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      color: Colors.white70,
    ),
  );

  // Emergency-specific text styles
  static TextStyle emergencyTitle(BuildContext context) {
    return OfflineFonts.rajdhani(
      fontSize: ResponsiveText._getScaleFactor(context) * 20,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: primaryRed,
      shadows: [
        Shadow(
          offset: Offset(0, 1),
          blurRadius: 2,
          color: Colors.black.withValues(alpha: 0.3),
        ),
      ],
    );
  }

  static TextStyle technicalData(BuildContext context) {
    return OfflineFonts.jetBrainsMono(
      fontSize: ResponsiveText._getScaleFactor(context) * 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: Colors.white70,
    );
  }

  static TextStyle statusIndicator(
    BuildContext context, {
    required Color color,
  }) {
    return OfflineFonts.rajdhani(
      fontSize: ResponsiveText._getScaleFactor(context) * 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      color: color,
    );
  }

  // Additional utility methods for emergency app
  static TextStyle emergencyButton(BuildContext context) {
    return OfflineFonts.rajdhani(
      fontSize: ResponsiveText._getScaleFactor(context) * 16,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      color: Colors.white,
    );
  }

  static TextStyle connectionStatus(
    BuildContext context, {
    required bool isConnected,
  }) {
    return OfflineFonts.inter(
      fontSize: ResponsiveText._getScaleFactor(context) * 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.3,
      color: isConnected ? safeGreen : primaryRed,
    );
  }

  static TextStyle deviceName(BuildContext context) {
    return OfflineFonts.inter(
      fontSize: ResponsiveText._getScaleFactor(context) * 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: Colors.white,
    );
  }

  static TextStyle timestamp(BuildContext context) {
    return OfflineFonts.inter(
      fontSize: ResponsiveText._getScaleFactor(context) * 11,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
      color: Colors.white54,
    );
  }

  static TextStyle messageContent(
    BuildContext context, {
    bool isEmergency = false,
  }) {
    return OfflineFonts.inter(
      fontSize: ResponsiveText._getScaleFactor(context) * 14,
      fontWeight: isEmergency ? FontWeight.w600 : FontWeight.w400,
      letterSpacing: 0.1,
      color: isEmergency ? Colors.white : Colors.white,
      height: 1.4,
    );
  }

  static TextStyle coordinates(BuildContext context) {
    return OfflineFonts.jetBrainsMono(
      fontSize: ResponsiveText._getScaleFactor(context) * 11,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: locationBlue,
    );
  }

  // Color schemes for different emergency levels
  static Color getEmergencyColor(String level) {
    switch (level.toLowerCase()) {
      case 'critical':
      case 'sos':
        return darkRed;
      case 'emergency':
      case 'danger':
        return primaryRed;
      case 'warning':
        return emergencyOrange;
      case 'caution':
        return warningYellow;
      case 'safe':
        return safeGreen;
      default:
        return offlineGray;
    }
  }

  // Gradient backgrounds for emergency states
  static LinearGradient getEmergencyGradient(String level) {
    final color = getEmergencyColor(level);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [color.withValues(alpha: 0.8), color.withValues(alpha: 0.6)],
    );
  }
}
