import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_flavor.dart';

/// Section 13.1 colour tokens. The only file (with the rest of core/theme) allowed to hold colour
/// literals: CI greps for `Color(0x` outside `lib/core/theme/`.
class AppPalette {
  const AppPalette({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.secondary,
    required this.accent,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.outline,
    required this.textPrimary,
    required this.textSecondary,
    required this.safe,
    required this.watch,
    required this.critical,
    required this.info,
    required this.flavorDriver,
    required this.flavorOperator,
    required this.flavorManager,
  });

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color secondary;
  final Color accent;
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color outline;
  final Color textPrimary;
  final Color textSecondary;
  final Color safe;
  final Color watch;
  final Color critical;
  final Color info;
  final Color flavorDriver;
  final Color flavorOperator;
  final Color flavorManager;

  Color flavorAccent(AppFlavor f) => switch (f) {
        AppFlavor.driver => flavorDriver,
        AppFlavor.operator => flavorOperator,
        AppFlavor.manager => flavorManager,
      };

  static const light = AppPalette(
    primary: Color(0xFF0B4F6C),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD4ECF5),
    secondary: Color(0xFF2E9D5B),
    accent: Color(0xFF12C2E9),
    background: Color(0xFFF4F8FA),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFE8F0F4),
    outline: Color(0xFFD0DCE3),
    textPrimary: Color(0xFF0F1C24),
    textSecondary: Color(0xFF55666F),
    safe: Color(0xFF15803D),
    watch: Color(0xFFB45309),
    critical: Color(0xFFB91C1C),
    info: Color(0xFF1D4ED8),
    flavorDriver: Color(0xFF12C2E9),
    flavorOperator: Color(0xFF2E9D5B),
    flavorManager: Color(0xFF5B5BD6),
  );

  static const dark = AppPalette(
    primary: Color(0xFF4FC3E8),
    onPrimary: Color(0xFF00222F),
    primaryContainer: Color(0xFF0F3A4C),
    secondary: Color(0xFF5CCB8A),
    accent: Color(0xFF12C2E9),
    background: Color(0xFF0A141A),
    surface: Color(0xFF111E26),
    surfaceVariant: Color(0xFF18303B),
    outline: Color(0xFF24404D),
    textPrimary: Color(0xFFE6F1F5),
    textSecondary: Color(0xFF93A8B3),
    safe: Color(0xFF4ADE80),
    watch: Color(0xFFFBBF24),
    critical: Color(0xFFF87171),
    info: Color(0xFF60A5FA),
    flavorDriver: Color(0xFF12C2E9),
    flavorOperator: Color(0xFF5CCB8A),
    flavorManager: Color(0xFF8B8BF0),
  );

  static AppPalette of(Brightness b) => b == Brightness.dark ? dark : light;

  /// Text drawn on a filled status colour (SOS button, filled secondary): white or dark ink,
  /// whichever contrasts more (dark-theme status colours are light, so they need dark text).
  Color onStatus(Color status) {
    const white = Color(0xFFFFFFFF);
    const ink = Color(0xFF0A141A);
    return contrastRatio(status, white) >= contrastRatio(status, ink) ? white : ink;
  }
}

/// Status of cargo/grades/alerts; never shown by colour alone (Section 13.3).
enum StatusLevel { safe, watch, critical, info }

extension StatusColor on AppPalette {
  Color status(StatusLevel s) => switch (s) {
        StatusLevel.safe => safe,
        StatusLevel.watch => watch,
        StatusLevel.critical => critical,
        StatusLevel.info => info,
      };
}

/// WCAG 2.x relative luminance.
double relativeLuminance(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// WCAG contrast ratio, 1–21.
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}
