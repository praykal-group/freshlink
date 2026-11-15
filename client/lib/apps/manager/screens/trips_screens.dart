import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/status.dart';
import '../data/models.dart';
import '../providers.dart';
import '../widgets/manager_widgets.dart';

final tripFilterProvider = NotifierProvider<TripFilter, (String?, DateTime)>(TripFilter.new);

class TripFilter extends Notifier<(String?, DateTime)> {
  @override
  (String?, DateTime) build() => (null, DateTime.now());
  void set(String? status, DateTime day) => state = (status, day);
}

final tripsProvider = FutureProvider.autoDispose<ApiPage>((ref) {
  final (status, day) = ref.watch(tripFilterProvider);
  return ref.watch(managerRepositoryProvider).trips(status: status, date: ymd(day));
});

const tripStatuses = ['PLANNED', 'ASSIGNED', 'PRE_CHECK_DONE', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'];

/// Section 10.6 #2: trips of a day, filtered by status.
class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final (status, day) = ref.watch(tripFilterProvider);
    final trips = ref.watch(tripsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.mgrTrips), actions: [
        IconButton(
          key: const Key('trips-date'),
          tooltip: l.changeDate,
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: day, firstDate: DateTime(2025), lastDate: DateTime.now().add(const Duration(days: 14)));
            if (d != null) ref.read(tripFilterProvider.notifier).set(status, d);
          },
          icon: const Icon(Icons.calendar_today_rounded),
        ),
      ]),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: Row(children: [
            Padding(padding: const EdgeInsets.only(right: AppSpacing.md), child: Text(DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).format(day), key: const Key('trips-day'))),
            for (final s in [null, ...tripStatuses])
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: ChoiceChip(label: Text(s ?? l.all), selected: status == s, onSelected: (_) => ref.read(tripFilterProvider.notifier).set(s, day)),
              ),
          ]),
        ),
        Expanded(
          child: AsyncView<ApiPage>(
            value: trips,
            onRetry: () => ref.invalidate(tripsProvider),
            isEmpty: (p) => p.items.isEmpty,
            empty: EmptyState(title: l.noTrips, icon: Icons.local_shipping_rounded),
            data: (p) => ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
              for (final t in p.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AppCard(
                    key: Key('trip-${t['code']}'),
                    status: tripLevel(t['status'] as String?),
                    onTap: () => context.go('/trips/${t['id']}'),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      TitleChip(title: '${t['code']}', chip: StatusChip(level: tripLevel(t['status'] as String?), label: '${t['status']}')),
                      Text([map(t['vehicle'])['regNo'] ?? '–', map(t['driver'])['name'] ?? l.noDriver, dateTimeText(context, date(t['plannedStart']))].join(' · ')),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

final tripDetailProvider = FutureProvider.autoDispose.family<(Map<String, dynamic>, Map<String, dynamic>), String>((ref, id) async {
  final repo = ref.watch(managerRepositoryProvider);
  final r = await Future.wait([repo.trip(id), repo.route(id)]);
  return (r[0], r[1]);
});

final tripTelemetryProvider = FutureProvider.autoDispose.family<TelemetrySeries, (String, DateTime, DateTime)>((ref, k) => ref.watch(managerRepositoryProvider).telemetry(k.$1, k.$2, k.$3));

/// Section 10.6 #2 detail: route versions, stops, telemetry with the safe band, emissions; Assign.
class TripDetailScreen extends ConsumerWidget {
  const TripDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final detail = ref.watch(tripDetailProvider(id));
    return Scaffold(
      appBar: AppBar(title: Text(detail.value?.$1['code'] as String? ?? l.mgrTrips)),
      body: AsyncView<(Map<String, dynamic>, Map<String, dynamic>)>(
        value: detail,
        onRetry: () => ref.invalidate(tripDetailProvider(id)),
        data: (d) {
          final (t, route) = d;
          final status = t['status'] as String?;
          final start = date(t['startedAt']) ?? date(t['plannedStart']) ?? DateTime.now();
          final end = date(t['completedAt']) ?? DateTime.now();
          return ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
            AppCard(
              status: tripLevel(status),
              child: Wrap(spacing: AppSpacing.xl, runSpacing: AppSpacing.sm, children: [
                _Fact(l.tripStatus, '$status'),
                _Fact(l.tripVehicleLabel, '${map(t['vehicle'])['regNo'] ?? '–'}'),
                _Fact(l.tripDriver, '${map(t['driver'])['name'] ?? l.noDriver}'),
                _Fact(l.tripDistance, t['distanceKm'] == null ? '–' : '${num0(t['distanceKm'])!.toStringAsFixed(1)} km'),
                _Fact(l.tripCo2, t['co2Kg'] == null ? '–' : '${num0(t['co2Kg'])!.toStringAsFixed(1)} kg CO₂'),
                _Fact(l.tripRouteVersion, 'v${route['currentVersion'] ?? 1}${route['pending'] != null ? ' (+v${map(route['pending'])['version']} ${l.proposed})' : ''}'),
              ]),
            ),
            if (status == 'PLANNED' || status == 'ASSIGNED') ...[
              const SizedBox(height: AppSpacing.md),
              AppButton(key: const Key('assign-open'), label: l.assignDriver, icon: Icons.person_add_alt_1_rounded, kind: AppButtonKind.tonal, onPressed: () async {
                if (await showAssignDialog(context, ref, id)) ref.invalidate(tripDetailProvider(id));
              }),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (status == 'IN_PROGRESS' || status == 'COMPLETED')
              Section(
                title: l.telemetryTitle,
                child: Consumer(builder: (context, ref, _) {
                  final series = ref.watch(tripTelemetryProvider((id, start, end.isAfter(start) ? end : start.add(const Duration(minutes: 1)))));
                  return AsyncView<TelemetrySeries>(
                    value: series,
                    skeleton: const Skeleton(height: 220),
                    isEmpty: (s) => s.points.isEmpty,
                    empty: EmptyState(title: l.noTelemetry, icon: Icons.thermostat_rounded),
                    data: (s) => TempChart(series: s),
                  );
                }),
              ),
            Section(
              title: l.stopsTitle,
              child: Column(children: [
                for (final s in maps(t['stops']))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(child: Text('${s['seq']}')),
                    title: Text('${map(s['site'])['name'] ?? map(s['buyer'])['name'] ?? s['type']}'),
                    subtitle: Text('${s['type']} · ETA ${dateTimeText(context, date(s['eta']))}'),
                    trailing: Text('${s['status']}', key: Key('stop-status-${s['seq']}')),
                  ),
              ]),
            ),
            Section(
              title: l.batchesOnTrip(maps(t['batches']).length),
              child: Column(children: [
                for (final b in maps(t['batches']))
                  ListTile(contentPadding: EdgeInsets.zero, title: Text('${b['code']}'), subtitle: Text('${localName(map(b['product']), Localizations.localeOf(context).languageCode)} · ${kg(num0(b['weightKg']))}'), trailing: Text('${b['status']}')),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ]);
}

/// Reefer temperature over time with the cargo's safe band (dashed limits, out-of-band points in
/// the critical colour, never colour alone: the count is written under the chart).
class TempChart extends StatelessWidget {
  const TempChart({super.key, required this.series});
  final TelemetrySeries series;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final pts = series.points.where((x) => x.tempC != null).toList();
    if (pts.isEmpty) return EmptyState(title: l.noTelemetry);
    final t0 = pts.first.at.millisecondsSinceEpoch.toDouble();
    double x(DateTime t) => (t.millisecondsSinceEpoch - t0) / 60000; // minutes since the first point
    final temps = pts.map((e) => e.tempC!);
    final lo = [temps.reduce(math.min), ?series.tempMin].reduce(math.min) - 1;
    final hi = [temps.reduce(math.max), ?series.tempMax].reduce(math.max) + 1;
    final fmt = DateFormat.Hm();
    final outX = {for (final e in pts) if (series.outOfBand(e)) x(e.at)};
    HorizontalLine limit(double y) => HorizontalLine(y: y, color: p.watch, strokeWidth: 1.5, dashArray: [6, 4], label: HorizontalLineLabel(show: true, labelResolver: (_) => '${y.toStringAsFixed(1)} °C', style: TextStyle(color: p.textSecondary, fontSize: 11)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 220,
        child: LineChart(
          key: const Key('temp-chart'),
          LineChartData(
            minY: lo,
            maxY: hi,
            gridData: const FlGridData(drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            extraLinesData: ExtraLinesData(horizontalLines: [if (series.tempMin != null) limit(series.tempMin!), if (series.tempMax != null) limit(series.tempMax!)]),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0), style: const TextStyle(fontSize: 11)))),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: math.max(1, x(pts.last.at) / 4),
                  getTitlesWidget: (v, _) => Text(fmt.format(DateTime.fromMillisecondsSinceEpoch((t0 + v * 60000).round())), style: const TextStyle(fontSize: 11)),
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [for (final e in pts) FlSpot(x(e.at), e.tempC!)],
                isCurved: false,
                color: p.primary,
                barWidth: 2,
                dotData: FlDotData(
                  checkToShowDot: (s, _) => outX.contains(s.x),
                  getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 3, color: p.critical, strokeWidth: 0),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        series.excursions == 0 ? l.chartAllInBand(pts.length) : l.chartExcursions(series.excursions, pts.length),
        key: const Key('chart-summary'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: series.excursions == 0 ? p.textSecondary : p.critical),
      ),
    ]);
  }
}

/// Section 10.6 #5 assign driver + vehicle (`POST /trips/:id/assign`). True when assigned.
Future<bool> showAssignDialog(BuildContext context, WidgetRef ref, String tripId) async {
  final l = context.l10n;
  final repo = ref.read(managerRepositoryProvider);
  late final List<Map<String, dynamic>> drivers, vehicles;
  try {
    final r = await Future.wait([repo.drivers(), repo.vehicles()]);
    drivers = r[0];
    vehicles = r[1].where((v) => v['active'] != false).toList();
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.loadFailed)));
    return false;
  }
  if (!context.mounted) return false;
  String? driverId, vehicleId;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(l.assignDriver),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            key: const Key('assign-driver'),
            isExpanded: true,
            decoration: InputDecoration(labelText: l.tripDriver),
            items: [for (final d in drivers) DropdownMenuItem(value: '${d['id']}', child: Text(d['busyTripCode'] == null ? '${d['name']}' : '${d['name']} (${d['busyTripCode']})', overflow: TextOverflow.ellipsis))],
            onChanged: (v) => set(() => driverId = v),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            key: const Key('assign-vehicle'),
            isExpanded: true,
            decoration: InputDecoration(labelText: l.tripVehicleLabel),
            items: [for (final v in vehicles) DropdownMenuItem(value: '${v['id']}', child: Text('${v['regNo']} · ${kg(num0(v['capacityKg']))}', overflow: TextOverflow.ellipsis))],
            onChanged: (v) => set(() => vehicleId = v),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
          FilledButton(key: const Key('assign-save'), onPressed: driverId == null || vehicleId == null ? null : () => Navigator.pop(c, true), child: Text(l.assign)),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return false;
  return runAndReport(context, () => repo.assign(tripId, driverId: driverId!, vehicleId: vehicleId!), success: l.tripAssigned);
}
