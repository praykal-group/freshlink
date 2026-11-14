import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../config/app_flavor.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Extra tokens Material's ColorScheme has no slot for (status colours, flavor accent).
@immutable
class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  const AppThemeTokens({required this.palette, required this.flavorAccent, required this.largeTargets});

  final AppPalette palette;
  final Color flavorAccent;
  final bool largeTargets;

  double get buttonHeight => largeTargets ? AppSizes.buttonHeightLarge : AppSizes.buttonHeight;
  double get minTarget => largeTargets ? AppSizes.minTargetLarge : AppSizes.minTarget;

  @override
  AppThemeTokens copyWith({AppPalette? palette, Color? flavorAccent, bool? largeTargets}) =>
      AppThemeTokens(palette: palette ?? this.palette, flavorAccent: flavorAccent ?? this.flavorAccent, largeTargets: largeTargets ?? this.largeTargets);

  @override
  AppThemeTokens lerp(ThemeExtension<AppThemeTokens>? other, double t) => t < 0.5 ? this : (other as AppThemeTokens? ?? this);
}

extension AppThemeContext on BuildContext {
  AppThemeTokens get tokens => Theme.of(this).extension<AppThemeTokens>()!;
  AppPalette get palette => tokens.palette;
}

class AppTheme {
  const AppTheme._();

  static ThemeData build(AppFlavor flavor, Brightness brightness) {
    final p = AppPalette.of(brightness);
    final tokens = AppThemeTokens(palette: p, flavorAccent: p.flavorAccent(flavor), largeTargets: flavor.largeTargets);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.primary,
      onPrimary: p.onPrimary,
      primaryContainer: p.primaryContainer,
      onPrimaryContainer: p.textPrimary,
      secondary: p.secondary,
      onSecondary: p.onStatus(p.secondary),
      secondaryContainer: p.surfaceVariant,
      onSecondaryContainer: p.textPrimary,
      tertiary: p.accent,
      onTertiary: p.textPrimary,
      error: p.critical,
      onError: p.onStatus(p.critical),
      surface: p.surface,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      surfaceContainerHighest: p.surfaceVariant,
      surfaceContainerHigh: p.surfaceVariant,
      surfaceContainer: p.surface,
      surfaceContainerLow: p.surface,
      surfaceContainerLowest: p.background,
      outline: p.outline,
      outlineVariant: p.outline,
    );
    final buttonSize = Size(64, tokens.buttonHeight);
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button));
    final text = AppTypography.textTheme(p.textPrimary, p.textSecondary);
    final reducedMotion = const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeThroughPageTransitionsBuilder(),
      TargetPlatform.iOS: FadeThroughPageTransitionsBuilder(),
      TargetPlatform.windows: FadeThroughPageTransitionsBuilder(),
      TargetPlatform.linux: FadeThroughPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeThroughPageTransitionsBuilder(),
    });

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      fontFamily: AppTypography.body,
      fontFamilyFallback: AppTypography.fallback,
      textTheme: text,
      extensions: [tokens],
      pageTransitionsTheme: reducedMotion,
      appBarTheme: AppBarTheme(backgroundColor: p.background, foregroundColor: p.textPrimary, elevation: 0, scrolledUnderElevation: 1, titleTextStyle: AppTypography.title.copyWith(color: p.textPrimary)),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card), side: BorderSide(color: p.outline)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: buttonSize, shape: buttonShape, textStyle: text.labelLarge)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: buttonSize, shape: buttonShape, textStyle: text.labelLarge, side: BorderSide(color: p.outline))),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: Size(48, tokens.minTarget), textStyle: text.labelLarge)),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: Size.square(tokens.minTarget))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceVariant,
        floatingLabelBehavior: FloatingLabelBehavior.never,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.input), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.input), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.input), borderSide: BorderSide(color: p.primary, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.input), borderSide: BorderSide(color: p.critical, width: 1.5)),
        helperStyle: text.bodySmall,
        errorStyle: AppTypography.bodySmall.copyWith(color: p.critical),
        errorMaxLines: 3,
        helperMaxLines: 3,
      ),
      chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip)), side: BorderSide(color: p.outline), labelStyle: text.labelMedium),
      bottomSheetTheme: const BottomSheetThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)))),
      navigationBarTheme: NavigationBarThemeData(backgroundColor: p.surface, indicatorColor: p.primaryContainer, labelTextStyle: WidgetStatePropertyAll(text.labelMedium)),
      navigationRailTheme: NavigationRailThemeData(backgroundColor: p.surface, indicatorColor: p.primaryContainer),
      dividerTheme: DividerThemeData(color: p.outline, space: 1),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button))),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}
