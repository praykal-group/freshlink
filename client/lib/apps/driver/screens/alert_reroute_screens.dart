import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/status.dart';
import '../data/models.dart';
import '../providers.dart';
import '../widgets/driver_widgets.dart';

/// What the driver should do, per alert type, in their language (the server message is English
/// and is shown under it).
String alertInstruction(AppLocalizations l, DriverAlert a) => switch (a.type) {
      'TEMP_EXCURSION' => l.alertTempDo,
      'DRIVER_FIX' => l.alertDriverFixDo,
      'SPOILAGE_RISK' => l.alertSpoilageDo,
      'HUMIDITY' => l.alertHumidityDo,
      'ETHYLENE' => l.alertEthyleneDo,
      'SHOCK' => l.alertShockDo,
      'DEVICE_OFFLINE' => l.alertDeviceDo,
      _ => l.alertGenericDo,
    };

String alertTitle(AppLocalizations l, DriverAlert a) => switch (a.type) {
      'TEMP_EXCURSION' => l.alertTemp,
      'DRIVER_FIX' => l.alertDriverFix,
      'SPOILAGE_RISK' => l.alertSpoilage,
      'HUMIDITY' => l.alertHumidity,
      'ETHYLENE' => l.alertEthylene,
      'SHOCK' => l.alertShock,
      'DEVICE_OFFLINE' => l.alertDevice,
      _ => l.alertGeneric,
    };

String ttsLanguage(String lang) => switch (lang) { 'hi' => 'hi-IN', 'mr' => 'mr-IN', _ => 'en-IN' };

/// Section 10.5 #5 / DA-FR-06/07: full screen, alarm + voice until Acknowledge. Never behind the
/// speed lock. Acknowledge works offline (queued; the alarm stops at once).
class AlertScreen extends ConsumerStatefulWidget {
  const AlertScreen({super.key, required this.alert});
  final DriverAlert alert;

  @override
  ConsumerState<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends ConsumerState<AlertScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l = context.l10n;
      final a = widget.alert;
      unawaited(ref.read(alertAlarmProvider).start(
            alertId: a.id,
            title: alertTitle(l, a),
            body: a.message,
            speech: '${alertTitle(l, a)}. ${alertInstruction(l, a)}',
            languageTag: ttsLanguage(Localizations.localeOf(context).languageCode),
          ));
    });
  }

  Future<void> _ack() async {
    setState(() => _busy = true);
    await ref.read(alertAlarmProvider).stop();
    await ref.read(driverRepositoryProvider).ackAlert(widget.alert.id);
    ref.read(attentionProvider.notifier).dismissAlert(widget.alert.id);
    unawaited(ref.read(syncSchedulerProvider)?.syncNow());
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final a = widget.alert;
    return PopScope(
      canPop: false, // only Acknowledge closes it (DA-FR-07)
      child: Scaffold(
        backgroundColor: p.critical,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Icon(Icons.warning_rounded, size: 72, color: p.onStatus(p.critical)),
                    const SizedBox(height: AppSpacing.md),
                    Text(alertTitle(l, a), key: const Key('alert-title'), style: AppTypography.headline.copyWith(color: p.onStatus(p.critical)), textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.lg),
                    Text(alertInstruction(l, a), key: const Key('alert-do'), style: AppTypography.subtitle.copyWith(color: p.onStatus(p.critical))),
                    if (a.message.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(a.message, style: TextStyle(color: p.onStatus(p.critical))),
                    ],
                  ]),
                ),
              ),
              SizedBox(
                height: 72,
                child: FilledButton.icon(
                  key: const Key('ack'),
                  style: FilledButton.styleFrom(backgroundColor: p.onStatus(p.critical), foregroundColor: p.critical, textStyle: AppTypography.title),
                  onPressed: _busy ? null : _ack,
                  icon: const Icon(Icons.check_circle_rounded, size: 32),
                  label: Text(l.acknowledge),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

String rerouteReasonText(AppLocalizations l, String r) => switch (r) {
      'DELAY' => l.reasonDelay,
      'INCIDENT' => l.reasonIncident,
      'DIVERSION' => l.reasonDiversion,
      'RESCUE' => l.reasonRescue,
      _ => l.reasonManual,
    };

/// Section 10.5 #6 / DA-FR-08: old stop vs new stop, reason, extra km; Accept (queued, the trip
/// view switches at once); Decline only for non-critical replans. Never behind the speed lock.
class RerouteScreen extends ConsumerStatefulWidget {
  const RerouteScreen({super.key, required this.proposal});
  final RouteProposal proposal;

  @override
  ConsumerState<RerouteScreen> createState() => _RerouteScreenState();
}

class _RerouteScreenState extends ConsumerState<RerouteScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _respond(bool accept) async {
    final trip = ref.read(currentTripProvider).value;
    if (trip == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(driverRepositoryProvider);
      if (accept) {
        await repo.acceptRoute(trip.id, widget.proposal.version);
        unawaited(ref.read(syncSchedulerProvider)?.syncNow());
      } else {
        await repo.declineRoute(trip.id, widget.proposal.version);
      }
      ref.read(attentionProvider.notifier).proposalHandled();
      await ref.read(currentTripProvider.notifier).reload();
      if (accept) {
        // navigation switches to the new next stop (DA-FR-08)
        final next = ref.read(currentTripProvider).value?.nextStop;
        if (next != null) unawaited(ref.read(navigateProvider)(next.lat, next.lng, next.name));
      }
      if (mounted) context.pop();
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final pr = widget.proposal;
    final (oldStop, newStop) = pr.changedStop;
    final t = Theme.of(context).textTheme;
    Widget stopBox(String label, TripStop? s, StatusLevel level, Key key) => AppCard(
          key: key,
          status: level,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: t.labelMedium),
            Text(s?.name ?? '–', style: t.titleMedium),
            if (s != null) Text([stopKindText(l, s.kind), l.stopEta(timeText(context, s.eta))].join(' · ')),
          ]),
        );
    return PopScope(
      canPop: pr.canDecline,
      child: Scaffold(
        appBar: AppBar(title: Text(l.rerouteTitle), automaticallyImplyLeading: pr.canDecline),
        body: ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
          AppCard(
            status: pr.canDecline ? StatusLevel.watch : StatusLevel.critical,
            child: Text(rerouteReasonText(l, pr.reason), key: const Key('reroute-reason'), style: t.titleSmall),
          ),
          const SizedBox(height: AppSpacing.md),
          stopBox(l.rerouteOld, oldStop, StatusLevel.info, const Key('reroute-old')),
          const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.xs), child: Icon(Icons.arrow_downward_rounded)),
          stopBox(l.rerouteNew, newStop, StatusLevel.safe, const Key('reroute-new')),
          const SizedBox(height: AppSpacing.md),
          if (pr.extraKm != null) Text(pr.extraKm! >= 0 ? l.rerouteExtraKm(pr.extraKm!.toStringAsFixed(1)) : l.rerouteShorterKm((-pr.extraKm!).toStringAsFixed(1)), key: const Key('reroute-km')),
          if (_error != null) ...[const SizedBox(height: AppSpacing.md), AppCard(status: StatusLevel.critical, child: Text(_error!))],
          const SizedBox(height: AppSpacing.xl),
          AppButton(key: const Key('reroute-accept'), label: l.acceptReroute, icon: Icons.check_rounded, busy: _busy, onPressed: _busy ? null : () => _respond(true)),
          if (pr.canDecline) ...[
            const SizedBox(height: AppSpacing.md),
            AppButton(key: const Key('reroute-decline'), label: l.declineReroute, kind: AppButtonKind.outlined, onPressed: _busy ? null : () => _respond(false)),
          ] else
            Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Text(l.rerouteMustAccept, style: t.bodySmall)),
        ]),
      ),
    );
  }
}
