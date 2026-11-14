import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iccms/core/config/app_flavor.dart';
import 'package:iccms/core/theme/app_colors.dart';
import 'package:iccms/core/theme/app_theme.dart';

void main() {
  group('WCAG AA contrast of every text/background pair in use (Section 13.1)', () {
    for (final (name, p) in [('light', AppPalette.light), ('dark', AppPalette.dark)]) {
      final pairs = <String, (Color, Color)>{
        'textPrimary on background': (p.textPrimary, p.background),
        'textPrimary on surface': (p.textPrimary, p.surface),
        'textPrimary on surfaceVariant (inputs)': (p.textPrimary, p.surfaceVariant),
        'textSecondary on background': (p.textSecondary, p.background),
        'textSecondary on surface': (p.textSecondary, p.surface),
        'textSecondary on surfaceVariant': (p.textSecondary, p.surfaceVariant),
        'onPrimary on primary (filled button)': (p.onPrimary, p.primary),
        'textPrimary on primaryContainer': (p.textPrimary, p.primaryContainer),
        'safe label on surface': (p.safe, p.surface),
        'watch label on surface': (p.watch, p.surface),
        'critical label on surface': (p.critical, p.surface),
        'info label on surface': (p.info, p.surface),
        'critical label on background': (p.critical, p.background),
        'text on filled critical (SOS)': (p.onStatus(p.critical), p.critical),
        'text on filled secondary': (p.onStatus(p.secondary), p.secondary),
      };
      pairs.forEach((pair, colors) {
        test('$name: $pair ≥ 4.5:1', () {
          final ratio = contrastRatio(colors.$1, colors.$2);
          expect(ratio, greaterThanOrEqualTo(4.5), reason: '$pair is ${ratio.toStringAsFixed(2)}:1');
        });
      });
    }
  });

  test('contrast math matches WCAG reference values', () {
    expect(contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)), closeTo(21, 0.01));
    expect(contrastRatio(const Color(0xFF777777), const Color(0xFFFFFFFF)), closeTo(4.48, 0.01));
  });

  test('every flavor builds a light and dark theme with its own accent', () {
    for (final f in AppFlavor.values) {
      for (final b in Brightness.values) {
        final t = AppTheme.build(f, b);
        expect(t.extension<AppThemeTokens>()!.flavorAccent, AppPalette.of(b).flavorAccent(f));
        expect(t.extension<AppThemeTokens>()!.buttonHeight, f == AppFlavor.manager ? 52 : 56);
      }
    }
    expect(AppPalette.light.flavorAccent(AppFlavor.driver), isNot(AppPalette.light.flavorAccent(AppFlavor.operator)));
  });

  test('no colour literal outside lib/core/theme (Section 13 lint rule)', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final path = f.path.replaceAll('\\', '/');
      if (!path.endsWith('.dart') || path.contains('lib/core/theme/') || path.contains('/generated/')) continue;
      if (f.readAsStringSync().contains('Color(0x')) offenders.add(path);
    }
    expect(offenders, isEmpty);
  });
}
