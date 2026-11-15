import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/env.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/connectivity.dart';
import '../../../shared/widgets/status.dart';
import '../data/models.dart';
import '../module_tag.dart';
import '../providers.dart';
import '../widgets/manager_widgets.dart';

/// Map tiles on/off (widget tests have no network for tiles).
final mapTilesProvider = Provider<bool>((_) => true);

/// Section 10.6 #1: KPI cards, live vehicle map (`vehicle.position`), latest alerts.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final summary = ref.watch(summaryProvider);
    final alerts = ref.watch(liveAlertsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.mgrDashboard), actions: [
        IconButton(tooltip: l.refresh, onPressed: () => ref.read(summaryProvider.notifier).refresh(), icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: Column(children: [
        const OfflineBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(summaryProvider.notifier).refresh(),
            child: ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
              AsyncView<ControlSummary>(
                value: summary,
                onRetry: () => ref.invalidate(summaryProvider),
                skeleton: const Skeleton(height: 120),
                data: (s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  CardGrid(children: [
                    KpiCard(key: const Key('kpi-active'), label: l.kpiActiveTrips, value: '${s.kpis.activeTrips}', icon: Icons.local_shipping_rounded, onTap: () => context.go('/trips')),
                    KpiCard(
                      key: const Key('kpi-critical'),
                      label: l.kpiCriticalAlerts,
                      value: '${s.kpis.openCriticalAlerts}',
                      icon: Icons.notification_important_rounded,
                      level: s.kpis.openCriticalAlerts > 0 ? StatusLevel.critical : StatusLevel.safe,
                      onTap: () => context.go('/alerts'),
                    ),
                    KpiCard(key: const Key('kpi-risk'), label: l.kpiAtRisk, value: '${s.kpis.atRiskBatches}', icon: Icons.hourglass_bottom_rounded, level: s.kpis.atRiskBatches > 0 ? StatusLevel.watch : null),
                    KpiCard(key: const Key('kpi-delivered'), label: l.kpiDeliveries, value: '${s.kpis.deliveriesToday}', icon: Icons.assignment_turned_in_rounded),
                    KpiCard(key: const Key('kpi-avoided'), label: l.kpiAvoided, value: kg(s.kpis.spoilageAvoidedKg), icon: Icons.eco_rounded, level: StatusLevel.safe),
                  ]),
                  const SizedBox(height: AppSpacing.lg),
                  Section(title: l.liveVehicles(s.vehicles.length), child: SizedBox(height: 320, child: _VehicleMap(vehicles: s.vehicles))),
                ]),
              ),
              Section(
                title: l.latestAlerts,
                action: TextButton(onPressed: () => context.go('/alerts'), child: Text(l.seeAll)),
                child: AsyncView<List<Map<String, dynamic>>>(
                  value: alerts,
                  skeleton: const SkeletonList(rows: 3),
                  isEmpty: (v) => v.isEmpty,
                  empty: EmptyState(title: l.noAlerts, icon: Icons.check_circle_rounded),
                  data: (v) => Column(children: [
                    for (final a in v.take(5))
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AppCard(
                          key: Key('dash-alert-${a['id']}'),
                          status: alertLevel(a['severity'] as String?, a['status'] as String?),
                          onTap: () => context.go('/alerts'),
                          child: Text('${a['type'] ?? ''} · ${a['message'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                  ]),
                ),
              ),
              Text(kModuleTag, key: const Key('module-tag'), style: Theme.of(context).textTheme.labelSmall, textAlign: TextAlign.center),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _VehicleMap extends ConsumerWidget {
  const _VehicleMap({required this.vehicles});
  final List<VehiclePosition> vehicles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final located = vehicles.where((v) => v.located).toList();
    final pts = [for (final v in located) LatLng(v.lat!, v.lng!)];
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(children: [
        FlutterMap(
          key: const Key('vehicle-map'),
          options: MapOptions(
            // Marathwada centre when no truck reports a position yet
            initialCenter: pts.isEmpty ? const LatLng(19.6, 75.6) : pts.first,
            initialZoom: 8,
            initialCameraFit: pts.length > 1 ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(48), maxZoom: 12) : null,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          ),
          children: [
            if (ref.watch(mapTilesProvider)) TileLayer(urlTemplate: Env.mapTileUrl, userAgentPackageName: 'in.iccms.manager'),
            MarkerLayer(markers: [
              for (final v in located)
                Marker(
                  point: LatLng(v.lat!, v.lng!),
                  width: 120,
                  height: 56,
                  child: GestureDetector(
                    onTap: v.tripId == null ? null : () => context.go('/trips/${v.tripId}'),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.local_shipping_rounded, color: p.primary, size: 28),
                      // the marker has a fixed size on the map: the label scales down to fit it
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(4)),
                            child: Text(v.regNo, key: Key('marker-${v.regNo}'), style: Theme.of(context).textTheme.labelSmall),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
            ]),
            RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors')]),
          ],
        ),
        if (vehicles.length > located.length)
          Positioned(
            left: 8,
            right: 8, // bounded width: AppCard lays out its text in an Expanded
            bottom: 8,
            child: AppCard(padding: const EdgeInsets.all(AppSpacing.sm), status: StatusLevel.watch, child: Text(context.l10n.vehiclesNoPosition(vehicles.length - located.length))),
          ),
      ]),
    );
  }
}
