import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/location/gps_fix.dart';
import '../../../core/providers.dart';
import '../../../core/tags/tag_reader.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/screens/camera_screen.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/status.dart';
import '../../../shared/widgets/tag_picker.dart';
import '../data/models.dart';
import '../providers.dart';
import '../widgets/driver_widgets.dart';

/// Saves the receiver's signature as a PNG for the POD_SIGNATURE upload. Tests override it.
typedef SignatureSaver = Future<({String path, int bytes})?> Function(SignatureController c);

Future<({String path, int bytes})?> saveSignaturePng(SignatureController c) async {
  final png = await c.toPngBytes();
  if (png == null) return null;
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/pod');
  await dir.create(recursive: true);
  final f = File('${dir.path}/sig-${DateTime.now().millisecondsSinceEpoch}.png');
  await f.writeAsBytes(png, flush: true);
  return (path: f.path, bytes: png.length);
}

final signatureSaverProvider = Provider<SignatureSaver>((_) => saveSignaturePng);

String podProblemText(AppLocalizations l, String p) => switch (p) {
      'scan' => l.podNeedScan,
      'tag' => l.podWrongTag,
      'kg' => l.podNeedKg,
      'reason' => l.podNeedReason,
      _ => p,
    };

/// Section 10.5 #8 / DA-FR-11/12: Arrive → scan each crate → outcome per batch → receiver →
/// signature → photo → Submit. Everything is queued offline.
class StopScreen extends ConsumerStatefulWidget {
  const StopScreen({super.key, required this.stopId});
  final String stopId;

  @override
  ConsumerState<StopScreen> createState() => _StopScreenState();
}

class _StopScreenState extends ConsumerState<StopScreen> {
  List<PodLine>? _lines;
  final _receiver = TextEditingController();
  // Paper-white in both themes: the signature is a PNG on white for the PoD record.
  final _signature = SignatureController(penStrokeWidth: 3, exportBackgroundColor: Colors.white);
  CapturedPhoto? _photo;
  String? _scanWarning;
  bool _showProblems = false;
  bool _busy = false;
  final _kg = <String, TextEditingController>{};
  final _reasons = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _signature.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _receiver.dispose();
    _signature.dispose();
    for (final c in [..._kg.values, ..._reasons.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onScan(DriverTrip trip, List<PodLine> lines, TagRead read) {
    final line = lines.where((x) => x.batch.matchesScan(read.uid)).firstOrNull;
    setState(() {
      if (line == null) {
        // a crate of another stop, or not on this truck: warn, do not record it
        final onTruck = trip.batches.any((b) => b.matchesScan(read.uid));
        _scanWarning = onTruck ? context.l10n.podOtherStop(read.uid) : context.l10n.podUnknownCrate(read.uid);
      } else {
        _scanWarning = null;
        line.scanned = read.uid;
      }
    });
  }

  Future<void> _arrive(DriverTrip trip, TripStop stop) async {
    setState(() => _busy = true);
    await ref.read(driverRepositoryProvider).arrive(trip.id, stop, at: ref.read(lastFixProvider));
    unawaited(ref.read(syncSchedulerProvider)?.syncNow());
    await ref.read(currentTripProvider.notifier).reload();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _photoTake() async {
    final l = context.l10n;
    final p = await ref.read(photoCaptureProvider)(context, title: l.podPhoto, instruction: l.podPhotoHint, fileStem: 'pod-${DateTime.now().millisecondsSinceEpoch}');
    if (p == null) return;
    unawaited(discardOriginal(p));
    if (mounted) setState(() => _photo = p);
  }

  List<String> _problems(AppLocalizations l, List<PodLine> lines) => [
        for (final x in lines)
          if (x.problem() case final p?) '${x.batch.code}: ${podProblemText(l, p)}',
        if (_receiver.text.trim().length < 2) l.podNeedReceiver,
        if (_signature.isEmpty) l.podNeedSignature,
        if (_photo == null) l.podNeedPhoto,
      ];

  Future<void> _submit(DriverTrip trip, TripStop stop, List<PodLine> lines) async {
    final l = context.l10n;
    for (final x in lines) {
      x.acceptedKg = parseNumber(_kg[x.batch.id]?.text ?? '');
      x.reason = _reasons[x.batch.id]?.text;
    }
    if (_problems(l, lines).isNotEmpty) {
      setState(() => _showProblems = true);
      return;
    }
    setState(() => _busy = true);
    final sig = await ref.read(signatureSaverProvider)(_signature);
    if (sig == null) {
      setState(() => _busy = false);
      return;
    }
    final fix = ref.read(lastFixProvider) ?? GpsFix(at: DateTime.now(), lat: stop.lat, lng: stop.lng); // no fix: the stop's own position
    await ref.read(driverRepositoryProvider).submitPod(trip.id, stop, lines: lines, receiverName: _receiver.text, signature: sig, photo: (path: _photo!.path, bytes: _photo!.sizeBytes), at: fix);
    unawaited(ref.read(syncSchedulerProvider)?.syncNow());
    await ref.read(currentTripProvider.notifier).reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.podSaved)));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final trip = ref.watch(currentTripProvider).value;
    final stop = trip?.stops.where((s) => s.id == widget.stopId).firstOrNull;
    if (trip == null || stop == null) return Scaffold(appBar: AppBar(), body: Center(child: Text(l.stopNotFound)));
    final t = Theme.of(context).textTheme;

    Widget body;
    if (stop.status == 'COMPLETED') {
      body = AppCard(status: StatusLevel.safe, child: Text(l.podDone, key: const Key('pod-done')));
    } else if (stop.status == 'PENDING') {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l.stopArriveHint),
        const SizedBox(height: AppSpacing.lg),
        AppButton(key: const Key('arrive'), label: l.arrived, icon: Icons.place_rounded, busy: _busy, onPressed: _busy ? null : () => _arrive(trip, stop)),
      ]);
    } else if (!stop.isDrop) {
      body = AppCard(child: Text(l.stopPickupHint));
    } else {
      final lines = _lines ??= [for (final b in trip.batchesFor(stop)) PodLine(b)];
      final problems = _showProblems ? _problems(l, lines) : const <String>[];
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l.podScanTitle(lines.where((x) => x.scanned != null).length, lines.length), style: t.titleMedium, key: const Key('pod-progress')),
        const SizedBox(height: AppSpacing.sm),
        TagPicker(onRead: (r) => _onScan(trip, lines, r)),
        if (_scanWarning != null) ...[const SizedBox(height: AppSpacing.sm), AppCard(key: const Key('pod-scan-warning'), status: StatusLevel.watch, child: Text(_scanWarning!))],
        const SizedBox(height: AppSpacing.lg),
        for (final x in lines) _PodLineCard(
          line: x,
          kg: _kg.putIfAbsent(x.batch.id, TextEditingController.new),
          reason: _reasons.putIfAbsent(x.batch.id, TextEditingController.new),
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(fieldKey: const Key('pod-receiver'), label: l.podReceiver, controller: _receiver, maxLength: 120, textInputAction: TextInputAction.done),
        const SizedBox(height: AppSpacing.md),
        Text(l.podSignature, style: t.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Container(
          decoration: BoxDecoration(border: Border.all(color: context.palette.outline), borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: Signature(key: const Key('pod-signature'), controller: _signature, height: 180, backgroundColor: Colors.white),
        ),
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _signature.clear, child: Text(l.clear))),
        AppButton(
          key: const Key('pod-photo'),
          label: _photo == null ? l.podPhoto : l.podPhotoDone,
          icon: _photo == null ? Icons.photo_camera_rounded : Icons.check_rounded,
          kind: AppButtonKind.outlined,
          onPressed: _photoTake,
        ),
        if (problems.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(key: const Key('pod-problems'), status: StatusLevel.critical, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final p in problems) Text('• $p')])),
        ],
        const SizedBox(height: AppSpacing.xl),
        AppButton(key: const Key('pod-submit'), label: l.podSubmit, icon: Icons.send_rounded, busy: _busy, onPressed: _busy ? null : () => _submit(trip, stop, lines)),
      ]);
    }

    return Scaffold(
      appBar: AppBar(title: Text(stop.name)),
      body: SpeedLockGate(
        child: ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
          Text([stopKindText(l, stop.kind), l.stopEta(timeText(context, stop.eta))].join(' · '), style: t.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          body,
        ]),
      ),
    );
  }
}

class _PodLineCard extends StatelessWidget {
  const _PodLineCard({required this.line, required this.kg, required this.reason, required this.onChanged});
  final PodLine line;
  final TextEditingController kg;
  final TextEditingController reason;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final b = line.batch;
    final scanned = line.scanned != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      // Not AppCard: its IntrinsicHeight under-measures text fields with counters (found in the
      // M12 flow test, 40 px overflow), so the status strip is a left border here.
      child: Container(
        key: Key('pod-line-${b.code}'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: context.palette.status(scanned ? StatusLevel.safe : StatusLevel.info), width: 6)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(scanned ? Icons.check_circle_rounded : Icons.qr_code_2_rounded, color: scanned ? context.palette.safe : null),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('${productName(b.product, lang)} · ${b.code}', style: Theme.of(context).textTheme.titleSmall)),
          ]),
          Text(l.podBatchWeight(b.weightKg.toStringAsFixed(1))),
          const SizedBox(height: AppSpacing.sm),
          SegmentedButton<String>(
            key: Key('pod-outcome-${b.code}'),
            segments: [
              ButtonSegment(value: 'ACCEPTED', label: Text(l.podAccepted), icon: const Icon(Icons.check_rounded)),
              ButtonSegment(value: 'PARTIAL', label: Text(l.podPartial), icon: const Icon(Icons.remove_rounded)),
              ButtonSegment(value: 'REJECTED', label: Text(l.podRejected), icon: const Icon(Icons.close_rounded)),
            ],
            selected: {line.outcome},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              line.outcome = s.first;
              onChanged();
            },
          ),
          if (line.outcome == 'PARTIAL') ...[
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              fieldKey: Key('pod-kg-${b.code}'),
              label: l.podAcceptedKg,
              unit: 'kg',
              controller: kg,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => Validators.numberInRange(v, min: 0.1, max: b.weightKg),
            ),
          ],
          if (line.outcome != 'ACCEPTED') ...[
            const SizedBox(height: AppSpacing.sm),
            AppTextField(fieldKey: Key('pod-reason-${b.code}'), label: l.podReason, controller: reason, maxLength: 500),
          ],
        ]),
      ),
    );
  }
}
