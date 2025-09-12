import 'package:flutter/material.dart';

class ResponsiveUtils {
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1024;
  static const double desktopBreakpoint = 1440;

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobileBreakpoint;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletBreakpoint;

  static bool isLandscape(BuildContext context) =>
      MediaQuery.of(context).orientation == Orientation.landscape;

  static bool isSmallScreen(BuildContext context) =>
      MediaQuery.of(context).size.height < 600;

  static double getResponsiveFontSize(BuildContext context, double baseSize) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) return baseSize * 0.85;
    if (width > tabletBreakpoint) return baseSize * 1.15;
    if (width > mobileBreakpoint) return baseSize * 1.05;
    return baseSize;
  }

  static double getResponsiveSpacing(BuildContext context, double baseSpacing) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) return baseSpacing * 0.8;
    if (width > tabletBreakpoint) return baseSpacing * 1.5;
    if (width > mobileBreakpoint) return baseSpacing * 1.2;
    return baseSpacing;
  }

  static EdgeInsets getResponsivePadding(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (isDesktop(context)) {
      return EdgeInsets.symmetric(
        horizontal: size.width * 0.15,
        vertical: size.height * 0.05,
      );
    } else if (isTablet(context)) {
      return EdgeInsets.symmetric(
        horizontal: size.width * 0.1,
        vertical: size.height * 0.04,
      );
    } else {
      return EdgeInsets.symmetric(
        horizontal: size.width * 0.06,
        vertical: size.height * 0.04,
      );
    }
  }

  static double getImageHeight(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (isLandscape(context)) {
      return size.height * 0.4;
    } else if (isSmallScreen(context)) {
      return 180;
    } else if (isDesktop(context)) {
      return size.height * 0.35;
    } else if (isTablet(context)) {
      return size.height * 0.32;
    } else {
      return size.height * 0.28;
    }
  }

  static double getMaxDialogWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (isDesktop(context)) return 400;
    if (isTablet(context)) return 350;
    return width * 0.9;
  }
}