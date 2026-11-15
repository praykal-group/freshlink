import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session.dart';
import '../../../core/config/env.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/location/trip_tracker.dart';
import '../../../core/map/caching_tile_provider.dart';
import '../../../core/map/corridor.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/connectivity.dart';
import '../../../shared/widgets/status.dart';
import '../data/models.dart';
import '../module_tag.dart';
import '../providers.dart';
import '../widgets/driver_widgets.dart';

String trackingProblemText(AppLocalizations l, TrackingProblem p) => switch (p) {
      TrackingProblem.locationOff => l.gpsOff,
      TrackingProblem.permissionDenied => l.gpsDenied,
      TrackingProblem.permissionDeniedForever => l.gpsDeniedForever,
      TrackingProblem.notificationsDenied => l.notificationsDenied,
      TrackingProblem.failed => l.gpsFailed,
    };

/// Driver home (Section 10.5 #1): today's trip card → pre-trip check → Start Trip.
class DriverTodayScreen extends ConsumerStatefulWidget {
  const DriverTodayScreen({super.key});

  @override
  ConsumerState<DriverTodayScreen> createState() => _DriverTodayScreenState();
}

class _DriverTodayScreenState extends ConsumerState<DriverTodayScreen> {
  bool _starting = false;
  TrackingProblem? _problem;
  String? _error;

  Future<void> _start(DriverTrip trip) async {
    final l = context.l10n;
    setState(() {
      _starting = true;
      _problem = null;
      _error = null;
    });
    final tracker = await ref.read(tripTrackerProvider.future);
    try {
      // 1. GPS + the "Trip in progress" service (DA-FR-10): permissions are asked here, at the depot.
      final interval = await ref.read(driverRepositoryProvider).gpsIntervalSec();
      final problem = await tracker?.start(tripCode: trip.code, title: l.tripInProgress(trip.code), text: l.tripInProgressText, gpsIntervalSec: interval);
      if (problem != null) {
        setState(() => _problem = problem);
        return;
      }
      // 2. The server binds this phone to the trip (409 TRIP_ON_OTHER_DEVICE etc.).
      try {
        await ref.read(driverRepositoryProvider).start(trip.id);
      } catch (_) {
        await tracker?.stop();
        rethrow;
      }
      await ref.read(currentTripProvider.notifier).refresh();
      unawaited(_prefetchTiles(trip));
      if (mounted) context.go('/trip');
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// DA-NFR-01: map tiles for the corridor, only where the tile provider allows bulk download (D-143).
  Future<void> _prefetchTiles(DriverTrip trip) async {
    if (!Env.mapTilePrefetch) return;
    final provider = await ref.read(tileProviderProvider.future);
    if (provider == null) return;
    await prefetchCorridor(provider, corridorTiles(trip.path));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final trip = ref.watch(currentTripProvider);
    final session = ref.watch(sessionProvider);
    final pending = ref.watch(pendingOpsProvider).value ?? 0;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.homeWelcome(session is SignedIn ? session.me.name : '')),
        actions: [
          IconButton(
            key: const Key('sync-badge'),
            tooltip: l.syncPending(pending),
            onPressed: () => context.push('/sync-queue'),
            icon: Badge(isLabelVisible: pending > 0, label: Text('$pending'), child: const Icon(Icons.sync_rounded)),
          ),
          IconButton(tooltip: l.settingsTitle, onPressed: () => context.push('/settings'), icon: const Icon(Icons.settings_rounded)),
        ],
      ),
      body: Column(children: [
        const OfflineBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(currentTripProvider.notifier).refresh(),
            child: ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
              AsyncView<DriverTrip?>(
                value: trip,
                onRetry: () => ref.read(currentTripProvider.notifier).refresh(),
                isEmpty: (v) => v == null,
                empty: EmptyState(title: l.noTripToday, message: l.noTripTodayHint, icon: Icons.local_shipping_rounded),
                data: (v) => _TripCard(trip: v!),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (trip.value case final DriverTrip tr) ...[
                if (_problem != null) ...[
                  AppCard(
                    status: StatusLevel.critical,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(trackingProblemText(l, _problem!), key: const Key('tracking-problem')),
                      if (_problem == TrackingProblem.locationOff || _problem == TrackingProblem.permissionDeniedForever)
                        TextButton(
                          onPressed: () => _problem == TrackingProblem.locationOff ? Geolocator.openLocationSettings() : Geolocator.openAppSettings(),
                          child: Text(l.openSettings),
                        ),
                    ]),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (_error != null) ...[
                  AppCard(status: StatusLevel.critical, child: Text(_error!, key: const Key('start-error'))),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (tr.inProgress)
                  AppButton(key: const Key('open-trip'), label: l.openTrip, icon: Icons.map_rounded, onPressed: () => context.go('/trip'))
                else ...[
                  AppButton(
                    key: const Key('pre-check'),
                    label: tr.preCheckDone ? l.preCheckAgain : l.preCheck,
                    icon: Icons.fact_check_rounded,
                    kind: tr.preCheckDone ? AppButtonKind.outlined : AppButtonKind.primary,
                    onPressed: () => context.push('/pre-check'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    key: const Key('start-trip'),
                    label: l.startTrip,
                    icon: Icons.play_arrow_rounded,
                    busy: _starting,
                    onPressed: tr.preCheckDone && !_starting ? () => _start(tr) : null,
                  ),
                  if (!tr.preCheckDone) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Text(l.startNeedsPreCheck, style: t.bodySmall)),
                ],
              ],
              const SizedBox(height: AppSpacing.md),
              AppButton(key: const Key('history'), label: l.tripHistory, icon: Icons.history_rounded, kind: AppButtonKind.outlined, onPressed: () => context.push('/history')),
              const SizedBox(height: AppSpacing.xl),
              Text(kModuleTag, key: const Key('module-tag'), style: t.labelSmall, textAlign: TextAlign.center),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});
  final DriverTrip trip;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return AppCard(
      key: const Key('trip-card'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(trip.code, style: t.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Wrap(spacing: AppSpacing.lg, runSpacing: AppSpacing.xs, children: [
          Text(l.tripVehicle(trip.vehicleRegNo ?? '–')),
          Text(l.tripBatches(trip.batches.length)),
          Text(l.tripStarts(timeText(context, trip.plannedStart))),
        ]),
        const Divider(height: AppSpacing.xl),
        for (final s in trip.stops)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 14, child: Text('${s.seq}')),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.name, style: t.titleSmall),
                  Text([stopKindText(l, s.kind), if (windowText(context, s).isNotEmpty) l.stopWindow(windowText(context, s))].join(' · '), style: t.bodySmall),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}
