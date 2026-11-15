import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/status.dart';
import '../data/models.dart';
import '../providers.dart';
import '../widgets/manager_widgets.dart';

final incidentsProvider = FutureProvider.autoDispose<ApiPage>((ref) => ref.watch(managerRepositoryProvider).incidents());

/// Section 10.6 #3: live alerts (ack / resolve) and incidents.
class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: Text(l.mgrAlerts), bottom: TabBar(tabs: [Tab(key: const Key('tab-alerts'), text: l.alertsTab), Tab(key: const Key('tab-incidents'), text: l.incidentsTab)])),
        body: const TabBarView(children: [_AlertList(), _IncidentList()]),
      ),
    );
  }
}

class _AlertList extends ConsumerWidget {
  const _AlertList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final alerts = ref.watch(liveAlertsProvider);
    final repo = ref.read(managerRepositoryProvider);
    return AsyncView<List<Map<String, dynamic>>>(
      value: alerts,
      onRetry: () => ref.invalidate(liveAlertsProvider),
      isEmpty: (v) => v.isEmpty,
      empty: EmptyState(title: l.noAlerts, icon: Icons.check_circle_rounded),
      data: (v) => RefreshIndicator(
        onRefresh: () => ref.read(liveAlertsProvider.notifier).refresh(),
        child: ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
          for (final a in v)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                key: Key('alert-${a['id']}'),
                status: alertLevel(a['severity'] as String?, a['status'] as String?),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TitleChip(title: '${a['type']}', chip: StatusChip(level: alertLevel(a['severity'] as String?, a['status'] as String?), label: '${a['severity']} · ${a['status']}')),
                  Text('${a['message'] ?? ''}'),
                  Text(dateTimeText(context, date(a['createdAt'])), style: Theme.of(context).textTheme.bodySmall),
                  if (a['status'] != 'RESOLVED')
                    Wrap(alignment: WrapAlignment.end, spacing: AppSpacing.sm, children: [
                      if (a['status'] == 'OPEN' || a['status'] == 'ESCALATED')
                        TextButton(
                          key: Key('ack-${a['id']}'),
                          onPressed: () async {
                            if (await runAndReport(context, () => repo.ackAlert('${a['id']}'))) await ref.read(liveAlertsProvider.notifier).refresh();
                          },
                          child: Text(l.acknowledge),
                        ),
                      TextButton(
                        key: Key('resolve-${a['id']}'),
                        onPressed: () async {
                          if (await runAndReport(context, () => repo.resolveAlert('${a['id']}'))) await ref.read(liveAlertsProvider.notifier).refresh();
                        },
                        child: Text(l.resolve),
                      ),
                      if (a['tripId'] != null) TextButton(onPressed: () => context.go('/trips/${a['tripId']}'), child: Text(l.openTrip)),
                    ]),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

StatusLevel incidentLevel(String? s) => switch (s) { 'RESOLVED' => StatusLevel.safe, 'FAILED' => StatusLevel.critical, 'ACTION_IN_PROGRESS' => StatusLevel.watch, _ => StatusLevel.critical };

class _IncidentList extends ConsumerWidget {
  const _IncidentList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return AsyncView<ApiPage>(
      value: ref.watch(incidentsProvider),
      onRetry: () => ref.invalidate(incidentsProvider),
      isEmpty: (p) => p.items.isEmpty,
      empty: EmptyState(title: l.noIncidents, icon: Icons.verified_rounded),
      data: (p) => ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
        for (final i in p.items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppCard(
              key: Key('incident-${i['id']}'),
              status: incidentLevel(i['status'] as String?),
              onTap: () => context.go('/incidents/${i['id']}'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TitleChip(title: '${i['kind']}', chip: StatusChip(level: incidentLevel(i['status'] as String?), label: '${i['status']}')),
                Text([if (i['decidedAction'] != null) '${i['decidedAction']}', l.incidentSteps((i['steps'] as num? ?? 0).toInt()), dateTimeText(context, date(i['createdAt']))].join(' · ')),
              ]),
            ),
          ),
      ]),
    );
  }
}

final incidentProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) => ref.watch(managerRepositoryProvider).incident(id));

/// Section 10.6 #3 detail: decision log, offers, manual actions (W-2) and resolve.
class IncidentDetailScreen extends ConsumerWidget {
  const IncidentDetailScreen({super.key, required this.id});
  final String id;

  Future<void> _act(BuildContext context, WidgetRef ref, String action) async {
    final l = context.l10n;
    final repo = ref.read(managerRepositoryProvider);
    String? buyerId, rescueTripId;
    if (action == 'DIVERT_BUYER' || action == 'DIVERT_COLD_STORAGE') {
      final buyers = (await repo.buyers()).items.where((b) => action == 'DIVERT_COLD_STORAGE' ? b['type'] == 'COLD_STORAGE' : b['type'] != 'COLD_STORAGE').toList();
      if (!context.mounted) return;
      buyerId = await _pick(context, l.pickBuyer, [for (final b in buyers) ('${b['id']}', '${b['name']} · ${b['type']}')]);
      if (buyerId == null) return;
    }
    if (action == 'RESCUE_PICKUP') {
      final trips = (await repo.trips(status: 'IN_PROGRESS')).items.where((t) => t['id'] != ref.read(incidentProvider(id)).value?['tripId']).toList();
      if (!context.mounted) return;
      rescueTripId = await _pick(context, l.pickRescueTrip, [for (final t in trips) ('${t['id']}', '${t['code']} · ${map(t['vehicle'])['regNo'] ?? ''}')]);
      if (rescueTripId == null) return;
    }
    if (!context.mounted || !await confirm(context, l.confirmAction(action))) return;
    if (!context.mounted) return;
    if (await runAndReport(context, () => repo.incidentAction(id, action, buyerId: buyerId, rescueTripId: rescueTripId), success: l.actionSent)) ref.invalidate(incidentProvider(id));
  }

  Future<String?> _pick(BuildContext context, String title, List<(String, String)> items) => showDialog<String>(
        context: context,
        builder: (c) => SimpleDialog(title: Text(title), children: [
          if (items.isEmpty) Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: Text(c.l10n.nothingToPick)),
          for (final (v, label) in items) SimpleDialogOption(key: Key('pick-$v'), onPressed: () => Navigator.pop(c, v), child: Text(label)),
        ]),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final inc = ref.watch(incidentProvider(id));
    return Scaffold(
      appBar: AppBar(title: Text(l.incidentTitle)),
      body: AsyncView<Map<String, dynamic>>(
        value: inc,
        onRetry: () => ref.invalidate(incidentProvider(id)),
        data: (i) {
          final open = i['status'] == 'OPEN' || i['status'] == 'ACTION_IN_PROGRESS';
          final log = maps(i['decisionLog']);
          return ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
            AppCard(
              status: incidentLevel(i['status'] as String?),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i['kind']} · ${i['status']}', key: const Key('incident-head'), style: Theme.of(context).textTheme.titleMedium),
                Text([map(i['trip'])['code'] ?? '', if (i['decidedAction'] != null) '→ ${i['decidedAction']}', if (map(i['rescueTrip'])['code'] != null) l.rescueBy('${map(i['rescueTrip'])['code']}')].join(' ')),
                TextButton(onPressed: () => context.go('/trips/${i['tripId']}'), child: Text(l.openTrip)),
              ]),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (open)
              Section(
                title: l.manualActions,
                child: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                  for (final a in const ['DRIVER_FIX', 'DIVERT_BUYER', 'DIVERT_COLD_STORAGE', 'RESCUE_PICKUP', 'REPLAN', 'MANUAL'])
                    OutlinedButton(key: Key('action-$a'), onPressed: () => _act(context, ref, a), child: Text(a)),
                ]),
              ),
            Section(
              title: l.offersTitle(maps(i['offers']).length),
              child: Column(children: [
                for (final o in maps(i['offers']))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${map(o['buyer'])['name'] ?? ''}'),
                    subtitle: Text('${kg(num0(o['quantityKg']))} · ${dateTimeText(context, date(o['createdAt']))}'),
                    trailing: Text('${o['status']}', key: Key('offer-${o['status']}')),
                  ),
              ]),
            ),
            Section(
              title: l.decisionLog(log.length),
              child: Column(children: [
                for (final e in log)
                  ListTile(
                    key: Key('log-${e['step']}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.circle, size: 10),
                    title: Text('${e['step']}'),
                    subtitle: Text([dateTimeText(context, date(e['at'])), if (e['by'] != null) '${e['by']}', if (e['reason'] != null) '${e['reason']}'].join(' · ')),
                  ),
              ]),
            ),
            if (open) ...[
              AppButton(
                key: const Key('incident-resolve'),
                label: l.resolve,
                icon: Icons.check_rounded,
                onPressed: () async {
                  if (await confirm(context, l.resolveIncident) && context.mounted && await runAndReport(context, () => ref.read(managerRepositoryProvider).resolveIncident(id))) ref.invalidate(incidentProvider(id));
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                key: const Key('incident-failed'),
                label: l.markFailed,
                kind: AppButtonKind.danger,
                onPressed: () async {
                  if (await confirm(context, l.markFailedConfirm, danger: true) && context.mounted && await runAndReport(context, () => ref.read(managerRepositoryProvider).resolveIncident(id, failed: true))) ref.invalidate(incidentProvider(id));
                },
              ),
            ],
          ]);
        },
      ),
    );
  }
}
