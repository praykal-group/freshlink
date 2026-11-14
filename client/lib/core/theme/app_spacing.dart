import 'package:flutter/widgets.dart';

/// Section 13.3 spacing, radii and sizes.
class AppSpacing {
  const AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;

  static const screenPhone = 16.0;
  static const screenTablet = 24.0;

  /// Navigation rail + multi-pane from this width (manager, Section 10.6).
  static const wideBreakpoint = 840.0;

  static double screenPadding(BuildContext context) => MediaQuery.sizeOf(context).width >= wideBreakpoint ? screenTablet : screenPhone;
}

class AppRadius {
  const AppRadius._();

  static const input = 10.0;
  static const chip = 10.0;
  static const button = 12.0;
  static const card = 16.0;
  static const sheet = 20.0;
}

class AppSizes {
  const AppSizes._();

  static const buttonHeight = 52.0;
  static const buttonHeightLarge = 56.0;
  static const minTarget = 48.0;
  static const minTargetLarge = 56.0;
  static const statusStrip = 4.0;
}

/// Section 13.4 motion tokens.
class AppMotion {
  const AppMotion._();

  static const micro = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 220);
  static const emphasised = Duration(milliseconds: 320);
  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const pressScale = 0.97;
  static const shimmerLoop = Duration(milliseconds: 1500);

  /// Reduce motion: no transitions beyond fade.
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
