import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/screens/camera_screen.dart';
import '../../../shared/widgets/status.dart';
import '../data/models.dart';
import '../providers.dart';

/// The camera screen keeps a full-size original for operator grading; driver photos (PoD,
/// incidents) only upload the compressed copy, so the original is deleted at once.
Future<void> discardOriginal(CapturedPhoto p) async {
  if (p.originalPath == p.path) return;
  try {
    await File(p.originalPath).delete();
  } on FileSystemException {
    // already gone
  }
}

/// A number typed with "." or "," (Validators.numberInRange accepts both).
double? parseNumber(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

/// Remaining shelf life → status (Section 13: never colour alone, always an icon + text too).
StatusLevel shelfLifeLevel(double? hours) => hours == null ? StatusLevel.info : hours < 12 ? StatusLevel.critical : hours < 36 ? StatusLevel.watch : StatusLevel.safe;

String shelfLifeText(AppLocalizations l, double? hours) {
  if (hours == null) return l.shelfLifeUnknown;
  if (hours <= 0) return l.shelfLifeExpired;
  final h = hours.floor();
  return h >= 48 ? l.shelfLifeDays((h / 24).floor(), h % 24) : l.shelfLifeHm(h, ((hours - h) * 60).round());
}

IconData levelIcon(StatusLevel s) => switch (s) {
      StatusLevel.safe => Icons.check_circle_rounded,
      StatusLevel.watch => Icons.warning_amber_rounded,
      StatusLevel.critical => Icons.error_rounded,
      StatusLevel.info => Icons.help_outline_rounded,
    };

String stopKindText(AppLocalizations l, StopKind k) => switch (k) {
      StopKind.pickup => l.stopPickup,
      StopKind.drop => l.stopDrop,
      StopKind.diversionDrop => l.stopDiversion,
      StopKind.rescuePickup => l.stopRescuePickup,
      StopKind.rescueDrop => l.stopRescueDrop,
      StopKind.coldStorageDrop => l.stopColdStorage,
    };

String timeText(BuildContext context, DateTime? t) => t == null ? '–' : DateFormat.Hm(Localizations.localeOf(context).toLanguageTag()).format(t);

String windowText(BuildContext context, TripStop s) =>
    s.windowStart == null && s.windowEnd == null ? '' : '${timeText(context, s.windowStart)}–${timeText(context, s.windowEnd)}';

/// Section 10.5 #3 "Navigate": Google Maps turn-by-turn (D-12), else any maps app via geo:.
typedef NavigateTo = Future<bool> Function(double lat, double lng, String label);

Future<bool> launchNavigation(double lat, double lng, String label) async {
  final google = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
  if (await canLaunchUrl(google) && await launchUrl(google)) return true;
  final geo = Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(label)})');
  return launchUrl(geo);
}

final navigateProvider = Provider<NavigateTo>((_) => launchNavigation);

/// DA-NFR-08: while the truck moves > 10 km/h the screen under this is blocked (a scrim takes every
/// tap; the keyboard closes). [essentials] (Navigate, SOS) stay usable on top of the scrim. Alert
/// and reroute screens are never wrapped: Acknowledge and Accept always work.
class SpeedLockGate extends ConsumerWidget {
  const SpeedLockGate({super.key, required this.child, this.essentials = const []});
  final Widget child;
  final List<Widget> essentials;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(speedLockProvider);
    if (locked) FocusManager.instance.primaryFocus?.unfocus();
    final l = context.l10n;
    return Stack(children: [
      child,
      if (locked)
        Positioned.fill(
          child: Semantics(
            container: true,
            label: l.speedLockTitle,
            child: ColoredBox(
              key: const Key('speed-lock'),
              color: context.palette.background.withValues(alpha: 0.94),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Icon(Icons.speed_rounded, size: 56, color: context.palette.watch),
                    const SizedBox(height: AppSpacing.md),
                    Text(l.speedLockTitle, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.sm),
                    Text(l.speedLockBody, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.xl),
                    for (final e in essentials) ...[e, const SizedBox(height: AppSpacing.md)],
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// Cargo strip on the trip screen (DA-FR-05): temperature, humidity, lowest shelf life.
class CargoStrip extends StatelessWidget {
  const CargoStrip({super.key, required this.cargo, this.onTap});
  final CargoStatus cargo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final low = cargo.lowestShelfLifeH;
    final level = cargo.tempOutOfRange ? StatusLevel.critical : shelfLifeLevel(low);
    final t = Theme.of(context).textTheme;
    Widget cell(IconData icon, String value, String label, {Key? key}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(icon, size: 18), const SizedBox(width: AppSpacing.xs), Flexible(child: Text(label, style: t.bodySmall, maxLines: 2))]),
            Text(value, key: key, style: AppTypography.subtitle.copyWith(color: context.palette.textPrimary), maxLines: 2),
          ]),
        );
    return AppCard(
      status: level,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          cell(Icons.thermostat_rounded, cargo.tempC == null ? '–' : '${cargo.tempC!.toStringAsFixed(1)} °C', l.cargoTemp, key: const Key('cargo-temp')),
          const SizedBox(width: AppSpacing.sm),
          cell(Icons.water_drop_rounded, cargo.humidityPct == null ? '–' : '${cargo.humidityPct!.round()} %', l.cargoHumidity),
        ]),
        const SizedBox(height: AppSpacing.sm),
        Row(children: [
          Icon(levelIcon(level), color: context.palette.status(level)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(l.cargoLowestShelfLife(shelfLifeText(l, low)), key: const Key('cargo-shelf'))),
        ]),
        if (cargo.fromCache && cargo.fetchedAt != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(l.cargoAsOf(timeText(context, cargo.fetchedAt)), style: t.bodySmall),
        ],
      ]),
    );
  }
}

/// The big red SOS button (DA-FR-14): works under the speed lock and offline (queued).
class SosButton extends StatelessWidget {
  const SosButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: 64,
      child: FilledButton.icon(
        key: const Key('sos'),
        style: FilledButton.styleFrom(backgroundColor: p.critical, foregroundColor: p.onStatus(p.critical), textStyle: AppTypography.title),
        onPressed: onPressed,
        icon: const Icon(Icons.sos_rounded, size: 32),
        label: Text(context.l10n.sos),
      ),
    );
  }
}
