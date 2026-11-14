import 'package:flutter/material.dart';

/// Section 13.2. Bundled fonts (assets/fonts, OFL): Poppins for headings, Noto Sans (+ Devanagari
/// fallback) for body text. Noto Sans files are variable fonts, so their weight is set with a
/// `wght` FontVariation as well as `fontWeight`.
class AppTypography {
  const AppTypography._();

  static const heading = 'Poppins';
  static const body = 'NotoSans';
  static const fallback = ['NotoSansDevanagari', 'Poppins'];

  static TextStyle _poppins(double size, double line) =>
      TextStyle(fontFamily: heading, fontFamilyFallback: const ['NotoSansDevanagari'], fontSize: size, height: line / size, fontWeight: FontWeight.w600);

  static TextStyle _noto(double size, double line, int weight) => TextStyle(
        fontFamily: body,
        fontFamilyFallback: fallback,
        fontSize: size,
        height: line / size,
        fontWeight: FontWeight.values[(weight ~/ 100) - 1],
        fontVariations: [FontVariation('wght', weight.toDouble())],
      );

  static final display = _poppins(32, 40);
  static final headline = _poppins(24, 32);
  static final title = _poppins(20, 28);
  static final subtitle = _noto(16, 24, 600);
  static final bodyText = _noto(15, 22, 400);
  static final bodySmall = _noto(13, 18, 400);
  static final label = _noto(13, 16, 500);

  /// Temperature / shelf-life numbers: tabular figures so they do not jump while animating.
  static final metric = _poppins(28, 32).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static TextTheme textTheme(Color primary, Color secondary) => TextTheme(
        displayLarge: display.copyWith(color: primary),
        displayMedium: display.copyWith(color: primary),
        displaySmall: display.copyWith(color: primary),
        headlineLarge: headline.copyWith(color: primary),
        headlineMedium: headline.copyWith(color: primary),
        headlineSmall: headline.copyWith(color: primary),
        titleLarge: title.copyWith(color: primary),
        titleMedium: subtitle.copyWith(color: primary),
        titleSmall: subtitle.copyWith(color: primary),
        bodyLarge: bodyText.copyWith(color: primary),
        bodyMedium: bodyText.copyWith(color: primary),
        bodySmall: bodySmall.copyWith(color: secondary),
        labelLarge: label.copyWith(color: primary, fontSize: 15),
        labelMedium: label.copyWith(color: primary),
        labelSmall: label.copyWith(color: secondary),
      );
}
