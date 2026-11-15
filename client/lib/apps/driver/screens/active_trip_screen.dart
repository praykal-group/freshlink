import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/env.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/connectivity.dart';
import '../../../shared/widgets/status.dart';
import '../data/models.dart';
import '../providers.dart';
import '../widgets/driver_widgets.dart';

/// Section 10.5 #3: map (route, truck, stops), next stop + Navigate, cargo strip, SOS, Report incident.
/// Alerts and reroute proposals open full screen from here as soon as they arrive.
class ActiveTripScreen extends ConsumerStatefulWidget {
  const ActiveTripScreen({super.key});

  @override
  ConsumerState<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends ConsumerState<ActiveTripScreen> {
  final _shownAlerts = <String>{};
  int? _shownProposal;

  void _onAttention(DriverAttention a) {
    final alert = a.topAlert;
    if (alert != null && alert.critical && !_shownAlerts.contains(alert.id)) {
      _shownAlerts.add(alert.id);
      context.push('/alert', extra: alert);
      return;
    }
    final p = a.proposal;
    if (p != null && _shownProposal != p.version) {
      _shownProposal = p.version;
      context.push('/reroute', extra: p);
    }
  }

  Future<void> _sos(DriverTrip trip) async {
    await ref.read(driverRepositoryProvider).sos(trip.id, at: ref.read(lastFixProvider));
    unawaited(ref.read(syncSchedulerProvider)?.syncNow());
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        key: const Key('sos-sent'),
        icon: Icon(Icons.sos_rounded, color: c.palette.critical, size: 40),
        title: Text(c.l10n.sosSent),
        content: Text(c.l10n.sosSentBody),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(c.l10n.ok))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    ref.watch(gpsDrainWorkerProvider);
    ref.listen<DriverAttention>(attentionProvider, (_, a) => _onAttention(a));
    final trip = ref.watch(currentTripProvider);
    final attention = ref.watch(attentionProvider);

    return AsyncView<DriverTrip?>(
      value: trip,
      onRetry: () => ref.read(currentTripProvider.notifier).refresh(),
      data: (tr) {
        if (tr == null) return Scaffold(appBar: AppBar(), body: EmptyState(title: l.noTripToday, icon: Icons.local_shipping_rounded));
        final next = tr.nextStop;
        final navigate = next == null
            ? null
            : AppButton(key: const Key('navigate'), label: l.navigate, icon: Icons.navigation_rounded, onPressed: () => ref.read(navigateProvider)(next.lat, next.lng, next.name));
        final sos = SosButton(onPressed: () => _sos(tr));
        return Scaffold(
          appBar: AppBar(
            title: Text(tr.code),
            actions: [
              IconButton(key: const Key('cargo-open'), tooltip: l.cargoStatus, onPressed: () => context.push('/cargo'), icon: const Icon(Icons.inventory_rounded)),
              IconButton(tooltip: l.tripHistory, onPressed: () => context.push('/history'), icon: const Icon(Icons.history_rounded)),
            ],
          ),
          body: SpeedLockGate(
            essentials: [?navigate, sos],
            child: Column(children: [
              const OfflineBanner(),
              Expanded(
                child: ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
                  if (attention.alerts.isNotEmpty) ...[
                    AppCard(
                      key: const Key('alert-banner'),
                      status: StatusLevel.critical,
                      onTap: () => context.push('/alert', extra: attention.topAlert),
                      child: Row(children: [
                        Icon(Icons.notification_important_rounded, color: context.palette.critical),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(l.openAlerts(attention.alerts.length))),
                      ]),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (attention.proposal != null) ...[
                    AppCard(
                      key: const Key('reroute-banner'),
                      status: StatusLevel.watch,
                      onTap: () => context.push('/reroute', extra: attention.proposal),
                      child: Text(l.rerouteWaiting),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  SizedBox(height: 240, child: _TripMap(trip: tr)),
                  const SizedBox(height: AppSpacing.md),
                  if (next == null)
                    AppCard(status: StatusLevel.safe, child: Text(l.allStopsDone, key: const Key('all-done')))
                  else
                    _NextStopCard(trip: tr, stop: next, navigate: navigate!),
                  const SizedBox(height: AppSpacing.md),
                  Consumer(builder: (context, ref, _) {
                    final cargo = ref.watch(cargoProvider(tr.id));
                    return AsyncView<CargoStatus>(
                      value: cargo,
                      skeleton: const Skeleton(height: 96),
                      data: (c) => CargoStrip(cargo: c, onTap: () => context.push('/cargo')),
                    );
                  }),
                  const SizedBox(height: AppSpacing.lg),
                  sos,
                  const SizedBox(height: AppSpacing.md),
                  AppButton(key: const Key('report-incident'), label: l.reportIncident, icon: Icons.report_rounded, kind: AppButtonKind.tonal, onPressed: () => context.push('/incident')),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _NextStopCard extends ConsumerWidget {
  const _NextStopCard({required this.trip, required this.stop, required this.navigate});
  final DriverTrip trip;
  final TripStop stop;
  final Widget navigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final window = windowText(context, stop);
    return AppCard(
      key: const Key('next-stop'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.nextStop, style: t.labelMedium),
        Text(stop.name, style: t.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Wrap(spacing: AppSpacing.lg, runSpacing: AppSpacing.xs, children: [
          Text(stopKindText(l, stop.kind)),
          Text(l.stopEta(timeText(context, stop.eta))),
          if (window.isNotEmpty) Text(l.stopWindow(window)),
        ]),
        const SizedBox(height: AppSpacing.md),
        navigate,
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          key: const Key('open-stop'),
          label: stop.status == 'ARRIVED' ? l.deliverHere : l.arrived,
          icon: stop.status == 'ARRIVED' ? Icons.assignment_turned_in_rounded : Icons.place_rounded,
          kind: AppButtonKind.tonal,
          onPressed: () => context.push('/stop/${stop.id}'),
        ),
      ]),
    );
  }
}

/// Route (straight stop-to-stop legs, D-143), stops and the truck. Tiles come through the disk
/// cache; without tiles (offline, nothing cached) the line and markers still show.
class _TripMap extends ConsumerWidget {
  const _TripMap({required this.trip});
  final DriverTrip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final tiles = ref.watch(tileProviderProvider).value;
    final fix = ref.watch(lastFixProvider);
    final pts = [for (final s in trip.stops) LatLng(s.lat, s.lng)];
    if (pts.isEmpty) return const SizedBox.shrink();
    final bounds = LatLngBounds.fromPoints([...pts, if (fix != null) LatLng(fix.lat, fix.lng)]);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: FlutterMap(
        key: const Key('trip-map'),
        options: MapOptions(
          initialCameraFit: pts.length > 1 ? CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(32)) : null,
          initialCenter: pts.first,
          initialZoom: 12,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        ),
        children: [
          if (tiles != null) TileLayer(urlTemplate: Env.mapTileUrl, tileProvider: tiles, userAgentPackageName: 'in.iccms.driver', maxNativeZoom: 18),
          PolylineLayer(polylines: [Polyline(points: pts, strokeWidth: 4, color: p.primary)]),
          MarkerLayer(markers: [
            for (final s in trip.stops)
              Marker(
                point: LatLng(s.lat, s.lng),
                width: 32,
                height: 32,
                child: CircleAvatar(backgroundColor: s.isOpen ? p.primary : p.safe, foregroundColor: p.onStatus(s.isOpen ? p.primary : p.safe), child: Text('${s.seq}')),
              ),
            if (fix != null) Marker(point: LatLng(fix.lat, fix.lng), width: 40, height: 40, child: Icon(Icons.local_shipping_rounded, color: p.critical, size: 36)),
          ]),
          RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors')]),
        ],
      ),
    );
  }
}
