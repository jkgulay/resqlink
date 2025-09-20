import 'package:flutter/material.dart';

class ResponsiveHelper {
  static bool isNarrow(BoxConstraints constraints) => constraints.maxWidth < 400;
  static bool isTablet(BuildContext context) => MediaQuery.of(context).size.width >= 768;
  static bool isDesktop(BuildContext context) => MediaQuery.of(context).size.width >= 1024;

  static EdgeInsets getCardMargins(BuildContext context) {
    if (isDesktop(context)) return EdgeInsets.symmetric(horizontal: 24, vertical: 6);
    if (isTablet(context)) return EdgeInsets.symmetric(horizontal: 16, vertical: 6);
    return EdgeInsets.symmetric(horizontal: 12, vertical: 6);
  }

  static EdgeInsets getCardPadding(BuildContext context) {
    if (isDesktop(context)) return EdgeInsets.all(32);
    if (isTablet(context)) return EdgeInsets.all(28);
    return EdgeInsets.all(24);
  }

  static BoxConstraints? getCardConstraints(BuildContext context) {
    return isDesktop(context) ? BoxConstraints(maxWidth: 1200) : null;
  }

  static double getContentSpacing(BuildContext context) {
    if (isDesktop(context)) return 24.0;
    if (isTablet(context)) return 22.0;
    return 20.0;
  }

  static double getSectionSpacing(BuildContext context) {
    if (isDesktop(context)) return 32.0;
    if (isTablet(context)) return 28.0;
    return 24.0;
  }

  static double getIconSize(BuildContext context, {double? narrow}) {
    if (isDesktop(context)) return 32.0;
    if (isTablet(context)) return 30.0;
    return narrow ?? 28.0;
  }

  static double getTitleSize(BuildContext context, {double? narrow}) {
    if (isDesktop(context)) return 24.0;
    if (isTablet(context)) return 22.0;
    return narrow ?? 20.0;
  }

  static double getSubtitleSize(BuildContext context, {double? narrow}) {
    if (isDesktop(context)) return 16.0;
    if (isTablet(context)) return 15.0;
    return narrow ?? 14.0;
  }

  static double getItemPadding(BuildContext context, {double? narrow}) {
    if (isDesktop(context)) return 20.0;
    if (isTablet(context)) return 19.0;
    return narrow ?? 18.0;
  }
}