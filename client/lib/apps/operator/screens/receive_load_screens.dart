import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/printing/label_printer.dart';
import '../../../core/providers.dart';
import '../../../core/tags/tag_reader.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/connectivity.dart';
import '../../../shared/widgets/status.dart';
import '../data/models.dart';
import '../data/operator_repository.dart';
import '../providers.dart';
import '../widgets/operator_widgets.dart';

// ───────────────────────── Receive (FO-FR-10) ─────────────────────────

/// Scan → batch summary → condition → damage photos → Accept / Partial (kg) / Reject (reason).
/// Finding the batch needs the network; the receipt itself is queued (works offline).
class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key});

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> {
  BatchItem? _batch;
  String _condition = 'GOOD';
  String _outcome = 'ACCEPTED';
  final _kg = TextEditingController();
  final _notes = TextEditingController();
  final _form = GlobalKey<FormState>();
  final List<CapturedPhoto> _photos = [];
  bool _busy = false;

  @override
  void dispose() {
    _kg.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _scanned(TagRead t) async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      final b = await ref.read(operatorRepositoryProvider).findByScan(t.uid);
      if (!mounted) return;
      if (b == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.notFound(t.uid))));
      } else {
        setState(() {
          _batch = b;
          _kg.text = b.weightKg.toString();
        });
      }
    } on AppException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.status == null ? l.onlineOnly : e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final l = context.l10n;
    final b = _batch!;
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(operatorRepositoryProvider);
      final fileIds = <String>[];
      for (final p in _photos) {
        fileIds.add(await repo.addReceivePhoto(p.path, p.sizeBytes));
      }
      final kg = _outcome == 'ACCEPTED' ? b.weightKg : (_outcome == 'REJECTED' ? 0.0 : double.parse(_kg.text.replaceAll(',', '.')));
      await repo.receive(b.id, ReceiveInput(outcome: _outcome, acceptedKg: kg, condition: _condition, notes: _notes.text, photoFileIds: fileIds));
      unawaited(ref.read(syncSchedulerProvider)?.syncNow());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.receiveSaved)));
      context.pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final b = _batch;
    final pad = AppSpacing.screenPadding(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.receive)),
      body: Column(children: [
        const OfflineBanner(),
        Expanded(
          child: Form(
            key: _form,
            child: ListView(padding: EdgeInsets.all(pad), children: [
              if (b == null) ...[
                Text(l.scanBatch, style: t.titleLarge),
                const SizedBox(height: AppSpacing.lg),
                if (_busy) const Center(child: CircularProgressIndicator()) else TagPicker(onRead: _scanned),
              ] else ...[
                AppCard(
                  status: batchStatusLevel(b.status),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.displayCode, key: const Key('receive-code'), style: t.titleMedium),
                    Text('${b.productName ?? ''} · ${b.weightKg.toStringAsFixed(1)} kg', style: t.bodyMedium),
                    if (b.grade != null) Padding(padding: const EdgeInsets.only(top: AppSpacing.xs), child: GradeChip(grade: b.grade!)),
                  ]),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(l.condition, style: t.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                Wrap(spacing: AppSpacing.sm, children: [
                  for (final (c, label) in [('GOOD', l.condGood), ('FAIR', l.condFair), ('POOR', l.condPoor)]) ChoiceChip(label: Text(label), selected: _condition == c, onSelected: (_) => setState(() => _condition = c)),
                ]),
                const SizedBox(height: AppSpacing.lg),
                Text(l.damagePhotos, style: t.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                  for (final p in _photos) Chip(label: Text('${p.sizeBytes ~/ 1024} KB'), avatar: const Icon(Icons.photo_rounded), onDeleted: () => setState(() => _photos.remove(p))),
                  if (_photos.length < 3)
                    ActionChip(
                      avatar: const Icon(Icons.add_a_photo_rounded),
                      label: Text(l.addPhoto),
                      onPressed: () async {
                        final shot = await ref.read(photoCaptureProvider)(context, title: l.damagePhotos, instruction: l.damagePhotos, fileStem: 'receive_${b.id}');
                        if (shot != null) setState(() => _photos.add(shot));
                      },
                    ),
                ]),
                const SizedBox(height: AppSpacing.lg),
                Text(l.outcome, style: t.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'ACCEPTED', label: Text(l.accept), icon: const Icon(Icons.check_rounded)),
                    ButtonSegment(value: 'PARTIAL', label: Text(l.partial)),
                    ButtonSegment(value: 'REJECTED', label: Text(l.reject), icon: const Icon(Icons.close_rounded)),
                  ],
                  selected: {_outcome},
                  onSelectionChanged: (s) => setState(() => _outcome = s.first),
                ),
                if (_outcome == 'PARTIAL') ...[
                  const SizedBox(height: AppSpacing.lg),
                  NumberField(fieldKey: const Key('accepted-kg'), label: l.acceptedWeight, controller: _kg, unit: 'kg', min: 0.1, max: b.weightKg, required: true),
                ],
                if (_outcome != 'ACCEPTED') ...[
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(controller: _notes, maxLines: 2, decoration: InputDecoration(hintText: l.reason), validator: (v) => (v ?? '').trim().length < 3 ? l.errorRequired : null),
                ],
              ],
            ]),
          ),
        ),
        if (b != null)
          SafeArea(
            top: false,
            minimum: EdgeInsets.fromLTRB(pad, AppSpacing.sm, pad, pad),
            child: AppButton(
              key: const Key('receive-submit'),
              label: _outcome == 'REJECTED' ? l.reject : l.submit,
              kind: _outcome == 'REJECTED' ? AppButtonKind.danger : AppButtonKind.primary,
              busy: _busy,
              onPressed: _submit,
            ),
          ),
      ]),
    );
  }
}

// ───────────────────────── Load truck (FO-FR-11) ─────────────────────────

/// Pick today's trip → scan crates (counter, wrong-batch warning when the batch is not allocated to
/// the trip) → confirm. The load is queued; the server re-checks every batch.
class LoadTruckScreen extends ConsumerStatefulWidget {
  const LoadTruckScreen({super.key});

  @override
  ConsumerState<LoadTruckScreen> createState() => _LoadTruckScreenState();
}

class _LoadTruckScreenState extends ConsumerState<LoadTruckScreen> {
  OperatorTrip? _trip;
  final _scanned = <String>{}; // batch ids
  String? _warning;
  bool _busy = false;

  /// Labels carry the batch code (QR → trace URL → code); a tag UID is resolved online.
  Future<void> _onScan(TagRead t) async {
    final l = context.l10n;
    final trip = _trip!;
    TripBatchRef? match = trip.allocated.where((a) => a.code == t.uid).firstOrNull;
    if (match == null && t.kind != TagKind.qr) {
      try {
        final b = await ref.read(operatorRepositoryProvider).findByScan(t.uid);
        if (b != null) match = trip.allocated.where((a) => a.id == b.id).firstOrNull ?? TripBatchRef(id: b.id, code: b.displayCode, weightKg: b.weightKg);
      } on AppException {
        // offline: unresolved tag → warning below
      }
    }
    final allocated = match != null && trip.allocated.any((a) => a.id == match!.id);
    setState(() {
      if (!allocated) {
        _warning = l.wrongBatch(match?.code ?? t.uid);
        HapticFeedback.heavyImpact();
      } else if (_scanned.contains(match!.id) || trip.loadedBatchIds.contains(match.id)) {
        _warning = l.alreadyScanned;
      } else {
        _warning = null;
        _scanned.add(match.id);
        HapticFeedback.mediumImpact();
      }
    });
  }

  Future<void> _confirm() async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      await ref.read(operatorRepositoryProvider).load(_trip!.id, _scanned.toList());
      unawaited(ref.read(syncSchedulerProvider)?.syncNow());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.loadSaved)));
      context.pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final pad = AppSpacing.screenPadding(context);
    final trip = _trip;
    if (trip == null) {
      final trips = ref.watch(operatorTripsProvider);
      return Scaffold(
        appBar: AppBar(title: Text(l.loadTruck)),
        body: Column(children: [
          const OfflineBanner(),
          Expanded(
            child: AsyncView<List<OperatorTrip>>(
              value: trips,
              onRetry: () => ref.invalidate(operatorTripsProvider),
              isEmpty: (x) => x.isEmpty,
              empty: EmptyState(icon: Icons.local_shipping_rounded, title: l.noTrips),
              data: (list) => ListView.separated(
                padding: EdgeInsets.all(pad),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (_, i) {
                  final tr = list[i];
                  return AppCard(
                    onTap: () => setState(() => _trip = tr),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr.code, style: t.titleMedium),
                      Text('${tr.vehicleRegNo} · ${tr.driverName ?? '–'} · ${DateFormat.Hm().format(tr.plannedStart.toLocal())}', style: t.bodyMedium),
                      Text(l.loadedCount(tr.loadedBatchIds.length, tr.allocated.length), style: t.bodySmall),
                    ]),
                  );
                },
              ),
            ),
          ),
        ]),
      );
    }
    final total = trip.allocated.length;
    final done = trip.loadedBatchIds.length + _scanned.length;
    return Scaffold(
      appBar: AppBar(title: Text(trip.code)),
      body: Column(children: [
        const OfflineBanner(),
        Expanded(
          child: ListView(padding: EdgeInsets.all(pad), children: [
            AppCard(
              status: done >= total ? StatusLevel.safe : StatusLevel.info,
              child: Text(l.loadedCount(done, total), key: const Key('load-count'), style: t.headlineSmall),
            ),
            if (_warning != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppCard(status: StatusLevel.critical, child: Row(children: [
                Icon(Icons.error_rounded, color: context.palette.critical),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(_warning!, key: const Key('load-warning'))),
              ])),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text(l.scanNext, style: t.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            TagPicker(onRead: _onScan),
            const SizedBox(height: AppSpacing.lg),
            for (final a in trip.allocated)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  (_scanned.contains(a.id) || trip.loadedBatchIds.contains(a.id)) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: (_scanned.contains(a.id) || trip.loadedBatchIds.contains(a.id)) ? context.palette.safe : null,
                ),
                title: Text(a.code),
                subtitle: Text('${a.weightKg.toStringAsFixed(1)} kg'),
              ),
          ]),
        ),
        SafeArea(
          top: false,
          minimum: EdgeInsets.fromLTRB(pad, AppSpacing.sm, pad, pad),
          child: AppButton(key: const Key('load-confirm'), label: l.confirmLoad, busy: _busy, onPressed: _scanned.isEmpty ? null : _confirm),
        ),
      ]),
    );
  }
}

// ───────────────────────── Printer setup ─────────────────────────

final _pairedProvider = FutureProvider.autoDispose((ref) => ref.watch(labelPrinterProvider).paired());

/// Bluetooth printer: pick a paired printer and run a test print (Section 10.4 #7).
class PrinterSetupScreen extends ConsumerWidget {
  const PrinterSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final paired = ref.watch(_pairedProvider);
    final selected = ref.watch(printerProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l.printer)),
      body: AsyncView(
        value: paired,
        onRetry: () => ref.invalidate(_pairedProvider),
        isEmpty: (list) => list.isEmpty,
        empty: EmptyState(icon: Icons.print_disabled_rounded, title: l.pairedPrinters, message: l.noPairedPrinters, actionLabel: l.retry, onAction: () => ref.invalidate(_pairedProvider)),
        data: (list) => ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
          Text(l.pairedPrinters, style: Theme.of(context).textTheme.titleMedium),
          RadioGroup<String>(
            groupValue: selected,
            onChanged: (v) => ref.read(printerProvider.notifier).select(v!),
            child: Column(children: [
              for (final p in list) RadioListTile<String>(value: p.macAdress, title: Text(p.name), subtitle: Text(p.macAdress)),
            ]),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: l.testPrint,
            icon: Icons.print_rounded,
            onPressed: selected == null
                ? null
                : () async {
                    final ok = await ref.read(labelPrinterProvider).print(
                          selected,
                          await labelBytes(LabelData(code: 'TEST-0001', productName: 'I-CCMS test', weightKg: 1, caughtOrHarvestedAt: DateTime.now(), sourceSite: 'Printer check', qrData: 'https://iccms.example/t/TEST-0001')),
                        );
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? l.printed : l.printFailed)));
                  },
          ),
          const SizedBox(height: AppSpacing.md),
          Text(l.noPairedPrinters, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}
