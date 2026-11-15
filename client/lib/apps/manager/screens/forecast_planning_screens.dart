import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/status.dart';
import '../data/models.dart';
import '../providers.dart';
import '../widgets/manager_widgets.dart';
import 'trips_screens.dart' show showAssignDialog;

String siteName(List<Map<String, dynamic>> sites, Object? id) => '${sites.where((s) => s['id'] == id).firstOrNull?['name'] ?? '–'}';

/// Section 10.6 #4: site + product → 7-day bars with range whiskers (lower..upper).
class ForecastScreen extends ConsumerStatefulWidget {
  const ForecastScreen({super.key});

  @override
  ConsumerState<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends ConsumerState<ForecastScreen> {
  String? _site;
  String? _product;
  Future<List<ForecastDay>>? _rows;
  String? _job;

  void _load() {
    if (_site == null || _product == null) return;
    final from = DateTime.now();
    final rows = ref.read(managerRepositoryProvider).forecast(siteId: _site!, productId: _product!, from: from, to: from.add(const Duration(days: 7)));
    setState(() {
      _rows = rows; // a block: an arrow would return the Future to setState (M13 test)
    });
  }

  Future<void> _run() async {
    final l = context.l10n;
    final repo = ref.read(managerRepositoryProvider);
    try {
      final id = await repo.runForecast();
      setState(() => _job = 'RUNNING');
      for (var i = 0; i < 120; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        final j = await repo.forecastJob(id);
        if (j['status'] != 'RUNNING') {
          if (mounted) setState(() => _job = '${j['status']}');
          break;
        }
      }
      _load();
    } on AppException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.code == 'FORECAST_RUNNING' ? l.forecastBusy : e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final sites = ref.watch(sitesProvider).where((s) => s['type'] == 'DISTRIBUTION_CENTRE').toList();
    final products = ref.watch(productsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.mgrForecast)),
      body: ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
        Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: [
          SizedBox(
            width: 280,
            child: DropdownButtonFormField<String>(
              key: const Key('fc-site'),
              isExpanded: true,
              decoration: InputDecoration(labelText: l.siteLabel),
              items: [for (final s in sites) DropdownMenuItem(value: '${s['id']}', child: Text('${s['name']}', overflow: TextOverflow.ellipsis))],
              onChanged: (v) {
                _site = v;
                _load();
              },
            ),
          ),
          SizedBox(
            width: 280,
            child: DropdownButtonFormField<String>(
              key: const Key('fc-product'),
              isExpanded: true,
              decoration: InputDecoration(labelText: l.productLabel),
              items: [for (final p in products) DropdownMenuItem(value: '${p['id']}', child: Text(localName(p, lang), overflow: TextOverflow.ellipsis))],
              onChanged: (v) {
                _product = v;
                _load();
              },
            ),
          ),
        ]),
        const SizedBox(height: AppSpacing.lg),
        if (_rows == null)
          EmptyState(title: l.pickSiteProduct, icon: Icons.insights_rounded)
        else
          FutureBuilder<List<ForecastDay>>(
            future: _rows,
            builder: (context, snap) {
              if (snap.hasError) return ErrorCard(error: snap.error!, onRetry: _load);
              if (!snap.hasData) return const Skeleton(height: 260);
              final rows = snap.data!;
              if (rows.isEmpty) return EmptyState(title: l.noForecast, icon: Icons.insights_rounded);
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ForecastChart(days: rows),
                const SizedBox(height: AppSpacing.sm),
                for (final d in rows)
                  Text('${DateFormat.MMMEd(lang).format(d.day)}: ${kg(d.predictedKg)} (${kg(d.lowerKg)} – ${kg(d.upperKg)})', key: Key('fc-row-${ymd(d.day)}')),
                if (rows.first.modelVersion != null) Text(l.modelVersion(rows.first.modelVersion!), style: Theme.of(context).textTheme.bodySmall),
              ]);
            },
          ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(key: const Key('fc-run'), label: _job == 'RUNNING' ? l.forecastRunning : l.runForecast, icon: Icons.play_arrow_rounded, kind: AppButtonKind.outlined, busy: _job == 'RUNNING', onPressed: _job == 'RUNNING' ? null : _run),
        if (_job != null && _job != 'RUNNING') Text(l.jobStatus(_job!), style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

/// Bars = predicted kg; the thin rod in each group = lower..upper (range whisker).
class ForecastChart extends StatelessWidget {
  const ForecastChart({super.key, required this.days});
  final List<ForecastDay> days;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final top = days.map((d) => d.upperKg).reduce(math.max) * 1.15;
    final lang = Localizations.localeOf(context).languageCode;
    return SizedBox(
      height: 260,
      child: BarChart(
        key: const Key('forecast-chart'),
        BarChartData(
          maxY: top <= 0 ? 1 : top,
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: (v, _) => Text(NumberFormat.compact().format(v), style: const TextStyle(fontSize: 11)))),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) => Text(DateFormat.E(lang).format(days[v.toInt()].day), style: const TextStyle(fontSize: 11)))),
          ),
          barGroups: [
            for (var i = 0; i < days.length; i++)
              BarChartGroupData(x: i, barsSpace: 2, barRods: [
                BarChartRodData(toY: days[i].predictedKg, width: 16, color: p.primary, borderRadius: BorderRadius.circular(3)),
                BarChartRodData(fromY: days[i].lowerKg, toY: days[i].upperKg, width: 3, color: p.textSecondary),
              ]),
          ],
        ),
      ),
    );
  }
}

/// Section 10.6 #5: Run planner → draft orders (edit qty / destination) → Approve → Build routes →
/// assign driver + vehicle.
class PlanningScreen extends ConsumerStatefulWidget {
  const PlanningScreen({super.key});

  @override
  ConsumerState<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends ConsumerState<PlanningScreen> {
  DateTime _day = DateTime.now().add(const Duration(days: 1));
  List<PlanNeed> _needs = const [];
  List<Map<String, dynamic>>? _orders;
  List<Map<String, dynamic>> _trips = const [];
  bool _busy = false;

  String get _date => ymd(_day);

  Future<void> _reloadOrders() async {
    final p = await ref.read(managerRepositoryProvider).orders(date: _date);
    if (mounted) setState(() => _orders = p.items.where((o) => o['status'] == 'DRAFT' || o['status'] == 'APPROVED' || o['status'] == 'PLANNED').toList());
  }

  Future<void> _step(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run() => _step(() async {
        final l = context.l10n;
        await runAndReport(context, () async {
          final r = await ref.read(managerRepositoryProvider).runPlanner(_date);
          _needs = [for (final n in maps(r['needs'])) PlanNeed.fromJson(n)];
          await _reloadOrders();
        }, success: l.plannerDone);
      });

  Future<void> _approveAll() => _step(() async {
        final repo = ref.read(managerRepositoryProvider);
        for (final o in [...?_orders].where((o) => o['status'] == 'DRAFT')) {
          if (!mounted || !await runAndReport(context, () => repo.approveOrder('${o['id']}'))) break;
        }
        await _reloadOrders();
      });

  Future<void> _build() async {
    final l = context.l10n;
    final sites = ref.read(sitesProvider);
    final depots = {for (final o in [...?_orders]) if (o['status'] == 'APPROVED') '${o['sourceSiteId']}'};
    if (depots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.noApprovedOrders)));
      return;
    }
    final depot = depots.length == 1
        ? depots.first
        : await showDialog<String>(
            context: context,
            builder: (c) => SimpleDialog(title: Text(l.pickDepot), children: [for (final d in depots) SimpleDialogOption(key: Key('depot-$d'), onPressed: () => Navigator.pop(c, d), child: Text(siteName(sites, d)))]),
          );
    if (depot == null || !mounted) return;
    await _step(() async {
      await runAndReport(context, () async {
        final r = await ref.read(managerRepositoryProvider).buildRoutes(_date, depot);
        _trips = maps(r['trips']);
        await _reloadOrders();
      }, success: l.routesBuilt);
    });
  }

  Future<void> _edit(Map<String, dynamic> o) async {
    final l = context.l10n;
    final sites = ref.read(sitesProvider).where((s) => s['type'] == 'DISTRIBUTION_CENTRE').toList();
    var dest = '${o['destinationSiteId']}';
    final r = await showDialog<Map<String, String>>(
      context: context,
      builder: (c) => TextFieldsDialog(
        title: l.editOrder('${o['code']}'),
        saveLabel: l.save,
        fields: [DialogField('order-qty', l.quantityKg, initial: num0(o['quantityKg'])?.toStringAsFixed(0) ?? '', keyboardType: const TextInputType.numberWithOptions(decimal: true), suffix: 'kg')],
        extra: (c) => DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: sites.any((s) => s['id'] == dest) ? dest : null,
          decoration: InputDecoration(labelText: l.destination),
          items: [for (final s in sites) DropdownMenuItem(value: '${s['id']}', child: Text('${s['name']}', overflow: TextOverflow.ellipsis))],
          onChanged: (v) => dest = v ?? dest,
        ),
      ),
    );
    if (r == null || !mounted) return;
    final q = double.tryParse(r['order-qty']!.trim().replaceAll(',', '.'));
    if (q == null || q <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.invalidQuantity)));
      return;
    }
    if (await runAndReport(context, () => ref.read(managerRepositoryProvider).editOrder('${o['id']}', quantityKg: q, destinationSiteId: dest == '${o['destinationSiteId']}' ? null : dest))) await _reloadOrders();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final sites = ref.watch(sitesProvider);
    final products = ref.watch(productsProvider);
    final orders = _orders;
    final drafts = orders?.where((o) => o['status'] == 'DRAFT').length ?? 0;
    final approved = orders?.where((o) => o['status'] == 'APPROVED').length ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(l.mgrPlanning)),
      body: ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(l.planFor(DateFormat.yMMMEd(lang).format(_day)), style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            key: const Key('plan-date'),
            tooltip: l.changeDate,
            onPressed: () async {
              final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 14)));
              if (d != null) {
                setState(() {
                  _day = d;
                  _orders = null;
                  _needs = const [];
                  _trips = const [];
                });
              }
            },
            icon: const Icon(Icons.calendar_month_rounded),
          ),
        ]),
        const SizedBox(height: AppSpacing.md),
        // 1. run → 2. approve → 3. build routes → 4. assign
        AppButton(key: const Key('plan-run'), label: l.runPlanner, icon: Icons.auto_awesome_rounded, busy: _busy, onPressed: _busy ? null : _run),
        if (orders == null) ...[
          const SizedBox(height: AppSpacing.sm),
          TextButton(key: const Key('plan-load'), onPressed: _reloadOrders, child: Text(l.loadExistingOrders)),
        ],
        if (_needs.isNotEmpty)
          Section(
            title: l.needsTitle,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(columns: [
                DataColumn(label: Text(l.siteLabel)),
                DataColumn(label: Text(l.productLabel)),
                DataColumn(label: Text(l.forecastKg), numeric: true),
                DataColumn(label: Text(l.onHandKg), numeric: true),
                DataColumn(label: Text(l.needKg), numeric: true),
                DataColumn(label: Text(l.shortfallKg), numeric: true),
              ], rows: [
                for (final n in _needs)
                  DataRow(cells: [DataCell(Text(n.siteCode)), DataCell(Text(n.productCode)), DataCell(Text(kg(n.forecastKg))), DataCell(Text(kg(n.onHandKg))), DataCell(Text(kg(n.needKg))), DataCell(Text(kg(n.shortfallKg), style: n.shortfallKg > 0 ? TextStyle(color: context.palette.critical) : null))]),
              ]),
            ),
          ),
        if (orders != null)
          Section(
            title: l.ordersTitle(orders.length),
            action: drafts > 0 ? TextButton(key: const Key('approve-all'), onPressed: _busy ? null : _approveAll, child: Text(l.approveAll(drafts))) : null,
            child: orders.isEmpty
                ? EmptyState(title: l.noOrders, icon: Icons.inbox_rounded)
                : Column(children: [
                    for (final o in orders)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AppCard(
                          key: Key('order-${o['code']}'),
                          status: o['status'] == 'DRAFT' ? StatusLevel.watch : StatusLevel.safe,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            TitleChip(title: '${o['code']}', chip: StatusChip(level: o['status'] == 'DRAFT' ? StatusLevel.watch : StatusLevel.safe, label: '${o['status']}')),
                            Text('${localName(products.where((p) => p['id'] == o['productId']).firstOrNull, lang)} · ${kg(num0(o['quantityKg']))}'),
                            Text('${siteName(sites, o['sourceSiteId'])} → ${siteName(sites, o['destinationSiteId'])}'),
                            if (o['status'] == 'DRAFT')
                              Wrap(alignment: WrapAlignment.end, spacing: AppSpacing.sm, children: [
                                TextButton(key: Key('edit-${o['code']}'), onPressed: _busy ? null : () => _edit(o), child: Text(l.edit)),
                                TextButton(
                                  key: Key('approve-${o['code']}'),
                                  onPressed: _busy ? null : () => _step(() async {
                                    if (await runAndReport(context, () => ref.read(managerRepositoryProvider).approveOrder('${o['id']}'))) await _reloadOrders();
                                  }),
                                  child: Text(l.approve),
                                ),
                              ]),
                          ]),
                        ),
                      ),
                  ]),
          ),
        if (approved > 0) AppButton(key: const Key('build-routes'), label: l.buildRoutes(approved), icon: Icons.route_rounded, kind: AppButtonKind.tonal, busy: _busy, onPressed: _busy ? null : _build),
        if (_trips.isNotEmpty)
          Section(
            title: l.tripsBuilt(_trips.length),
            child: Column(children: [
              for (final t in _trips)
                ListTile(
                  key: Key('built-${t['code']}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text('${t['code']}'),
                  subtitle: Text('${num0(t['distanceKm'])?.toStringAsFixed(1) ?? '–'} km · ${kg(num0(t['loadKg']))} · ${maps(t['stops']).length} ${l.stopsTitle.toLowerCase()}'),
                  trailing: TextButton(key: Key('assign-${t['code']}'), onPressed: () => showAssignDialog(context, ref, '${t['id']}'), child: Text(l.assign)),
                ),
            ]),
          ),
      ]),
    );
  }
}
