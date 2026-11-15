import 'dart:async';
import 'dart:io';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/printing/label_printer.dart';
import '../../../core/providers.dart';
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

const _views = ['TOP', 'SIDE', 'CLOSEUP'];
const kWizardSteps = 7;

/// Client ranges for on-device validation (FO-NFR-07); the server DTO ranges are wider.
class FieldRanges {
  static const weight = (min: 0.1, max: 50000.0);
  static const fishCoreTemp = (min: -2.0, max: 10.0); // spec example
  static const iceRatio = (min: 0.0, max: 5.0);
  static const maturity = (min: 0.0, max: 10.0);
  static const brix = (min: 0.0, max: 40.0);
  static const fieldTemp = (min: -10.0, max: 55.0);
  static const humidity = (min: 0.0, max: 100.0);
}

/// New Batch wizard (Section 10.4): Form → Tag → Photos → Grade → Storage → Label → Done. The draft
/// is saved after every step (resumable after the app is closed); everything up to the photos is
/// queued in the outbox, so a batch is registered fully offline (FO-NFR-01).
class BatchWizardScreen extends ConsumerStatefulWidget {
  const BatchWizardScreen({super.key, required this.category, this.resume = false});
  final String category; // FISH | PRODUCE
  final bool resume;

  @override
  ConsumerState<BatchWizardScreen> createState() => _BatchWizardScreenState();
}

class _BatchWizardScreenState extends ConsumerState<BatchWizardScreen> {
  WizardDraft? _draft;
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider)!;
    WizardDraft? d = widget.resume ? await db.loadDraft() : null;
    if (d == null) {
      d = WizardDraft(category: widget.category, startedAt: DateTime.now());
      final last = await ref.read(operatorRepositoryProvider).lastUsed(widget.category);
      d.form.addAll(last);
      await db.saveDraft(d);
      ref.invalidate(operatorDraftProvider);
    }
    if (mounted) setState(() => _draft = d);
  }

  Future<void> _go(int step) async {
    final d = _draft!;
    setState(() {
      _forward = step > d.step;
      d.step = step;
    });
    await ref.read(databaseProvider)!.saveDraft(d);
    ref.invalidate(operatorDraftProvider);
  }

  Future<void> _save() async {
    await ref.read(databaseProvider)!.saveDraft(_draft!);
    ref.invalidate(operatorDraftProvider);
  }

  void _syncSoon() => unawaited(ref.read(syncSchedulerProvider)?.syncNow());

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final d = _draft;
    if (d == null) return const Scaffold(body: SkeletonList());
    final titles = [l.stepForm, l.stepTag, l.stepPhotos, l.stepGrade, l.stepStorage, l.stepLabel, l.stepDone];
    final step = d.step.clamp(0, kWizardSteps - 1);
    final body = switch (step) {
      0 => _FormStep(draft: d, onDone: () async {
          _syncSoon();
          await _go(1);
        }),
      1 => _TagStep(draft: d, save: _save, onDone: () async {
          _syncSoon();
          await _go(2);
        }),
      2 => _PhotosStep(draft: d, save: _save, onDone: () async {
          _syncSoon();
          await _go(3);
        }),
      3 => _GradeStep(draft: d, save: _save, onDone: () => _go(4)),
      4 => _StorageStep(draft: d, save: _save, onDone: () => _go(5)),
      5 => _LabelStep(draft: d, onDone: () => _go(6)),
      _ => _DoneStep(draft: d),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category == 'FISH' ? l.newFishBatch : l.newProduceBatch),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
            child: Row(children: [
              Expanded(child: Text('${l.stepOf(step + 1, kWizardSteps)} · ${titles[step]}', style: Theme.of(context).textTheme.labelLarge, overflow: TextOverflow.ellipsis)),
              SizedBox(width: 96, child: LinearProgressIndicator(value: (step + 1) / kWizardSteps, minHeight: 6, borderRadius: BorderRadius.circular(3))),
            ]),
          ),
        ),
      ),
      body: Column(children: [
        const OfflineBanner(),
        Expanded(
          child: PageTransitionSwitcher(
            duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.emphasised,
            reverse: !_forward,
            transitionBuilder: (child, a, b) => SharedAxisTransition(animation: a, secondaryAnimation: b, transitionType: SharedAxisTransitionType.horizontal, child: child),
            child: KeyedSubtree(key: ValueKey(step), child: body),
          ),
        ),
      ]),
    );
  }
}

/// Scrollable step body with the primary action pinned at the bottom (one primary button per screen).
class _StepScaffold extends StatelessWidget {
  const _StepScaffold({required this.children, required this.action, this.secondary});
  final List<Widget> children;
  final Widget action;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.screenPadding(context);
    return Column(children: [
      Expanded(child: ListView(padding: EdgeInsets.all(pad), children: children)),
      SafeArea(
        top: false,
        minimum: EdgeInsets.fromLTRB(pad, AppSpacing.sm, pad, pad),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ?secondary,
          if (secondary != null) const SizedBox(height: AppSpacing.sm),
          action,
        ]),
      ),
    ]);
  }
}

// ───────────────────────── 1. Form (FO-FR-02/03/04) ─────────────────────────

class _FormStep extends ConsumerStatefulWidget {
  const _FormStep({required this.draft, required this.onDone});
  final WizardDraft draft;
  final Future<void> Function() onDone;

  @override
  ConsumerState<_FormStep> createState() => _FormStepState();
}

class _FormStepState extends ConsumerState<_FormStep> {
  final _form = GlobalKey<FormState>();
  final _c = <String, TextEditingController>{};
  String? _productId;
  late DateTime _time;
  bool _busy = false;

  bool get _fish => widget.draft.category == 'FISH';
  List<String> get _fields => _fish ? ['weightKg', 'vesselId', 'iceToFishRatio', 'initialCoreTemp'] : ['weightKg', 'farmRef', 'maturityIndex', 'brix', 'fieldTemp', 'fieldHumidity'];

  @override
  void initState() {
    super.initState();
    final f = widget.draft.form;
    for (final k in _fields) {
      // Last-used values pre-fill the slow-changing fields (vessel, farm, ratios); weight and
      // temperatures are per batch and stay empty.
      final keep = !{'weightKg', 'initialCoreTemp', 'fieldTemp', 'fieldHumidity'}.contains(k) || f['draftOwn'] == true;
      _c[k] = TextEditingController(text: keep && f[k] != null ? '${f[k]}' : '');
    }
    _productId = f['productId'] as String?;
    _time = f['caughtOrHarvestedAt'] != null && f['draftOwn'] == true ? DateTime.parse(f['caughtOrHarvestedAt'] as String).toLocal() : DateTime.now();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  double? _n(String k) => double.tryParse(_c[k]!.text.trim().replaceAll(',', '.'));

  Future<void> _pickTime() async {
    final date = await showDatePicker(context: context, initialDate: _time, firstDate: DateTime.now().subtract(const Duration(days: 14)), lastDate: DateTime.now());
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_time));
    if (time == null) return;
    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => _time = picked.isAfter(DateTime.now()) ? DateTime.now() : picked);
  }

  Future<void> _submit(Masters m) async {
    if (_productId == null || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final repo = ref.read(operatorRepositoryProvider);
    final draft = BatchDraft(
      productId: _productId!,
      caughtOrHarvestedAt: _time,
      weightKg: _n('weightKg')!,
      vesselId: _fish && _c['vesselId']!.text.trim().isNotEmpty ? _c['vesselId']!.text.trim() : null,
      farmRef: !_fish && _c['farmRef']!.text.trim().isNotEmpty ? _c['farmRef']!.text.trim() : null,
      iceToFishRatio: _fish ? _n('iceToFishRatio') : null,
      initialCoreTemp: _fish ? _n('initialCoreTemp') : null,
      maturityIndex: _fish ? null : _n('maturityIndex'),
      brix: _fish ? null : _n('brix'),
      fieldTemp: _fish ? null : _n('fieldTemp'),
      fieldHumidity: _fish ? null : _n('fieldHumidity'),
    );
    try {
      widget.draft.batchId ??= await repo.createBatch(draft);
      widget.draft.form
        ..addAll({'productId': _productId, 'caughtOrHarvestedAt': _time.toUtc().toIso8601String(), 'draftOwn': true})
        ..addAll({for (final k in _fields) k: _c[k]!.text.trim()});
      await repo.saveLastUsed(widget.draft.category, {
        'productId': _productId,
        if (_fish) ...{'vesselId': draft.vesselId, 'iceToFishRatio': draft.iceToFishRatio} else ...{'farmRef': draft.farmRef, 'maturityIndex': draft.maturityIndex, 'brix': draft.brix},
      });
      await widget.onDone();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = ref.watch(localeProvider).languageCode;
    final masters = ref.watch(mastersProvider);
    final fmt = DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).add_Hm();
    return AsyncView<Masters>(
      value: masters,
      onRetry: () => ref.invalidate(mastersProvider),
      data: (m) {
        final products = m.byCategory(widget.draft.category);
        if (_productId != null && products.every((p) => p.id != _productId)) _productId = null;
        final created = widget.draft.batchId != null;
        return Form(
          key: _form,
          child: _StepScaffold(
            action: AppButton(key: const Key('form-next'), label: l.next, busy: _busy, onPressed: () => _submit(m)),
            children: [
              if (m.fromCache) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.md), child: StaleLabel(updatedAt: m.fetchedAt)),
              Text(l.product, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                for (final p in products)
                  ChoiceChip(
                    key: Key('product-${p.code}'),
                    label: Text(p.localName(lang)),
                    selected: _productId == p.id,
                    onSelected: created ? null : (_) => setState(() => _productId = p.id),
                  ),
              ]),
              if (_productId == null) Padding(padding: const EdgeInsets.only(top: AppSpacing.xs), child: Text(l.errorRequired, style: TextStyle(color: context.palette.critical))),
              const SizedBox(height: AppSpacing.lg),
              Text(_fish ? l.catchTime : l.harvestTime, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              OutlinedButton.icon(onPressed: created ? null : _pickTime, icon: const Icon(Icons.schedule_rounded), label: Text(fmt.format(_time))),
              const SizedBox(height: AppSpacing.lg),
              NumberField(fieldKey: const Key('weightKg'), label: l.weight, controller: _c['weightKg']!, unit: 'kg', min: FieldRanges.weight.min, max: FieldRanges.weight.max, required: true),
              const SizedBox(height: AppSpacing.lg),
              if (_fish) ...[
                _text(l.vesselId, 'vesselId', 40),
                const SizedBox(height: AppSpacing.lg),
                NumberField(label: l.iceRatio, controller: _c['iceToFishRatio']!, min: FieldRanges.iceRatio.min, max: FieldRanges.iceRatio.max),
                const SizedBox(height: AppSpacing.lg),
                NumberField(fieldKey: const Key('coreTemp'), label: l.coreTemp, controller: _c['initialCoreTemp']!, unit: '°C', min: FieldRanges.fishCoreTemp.min, max: FieldRanges.fishCoreTemp.max, required: true),
              ] else ...[
                _text(l.farmRef, 'farmRef', 60),
                const SizedBox(height: AppSpacing.lg),
                NumberField(label: l.maturity, controller: _c['maturityIndex']!, min: FieldRanges.maturity.min, max: FieldRanges.maturity.max),
                const SizedBox(height: AppSpacing.lg),
                NumberField(label: l.brix, controller: _c['brix']!, unit: '°Bx', min: FieldRanges.brix.min, max: FieldRanges.brix.max),
                const SizedBox(height: AppSpacing.lg),
                NumberField(label: l.fieldTemp, controller: _c['fieldTemp']!, unit: '°C', min: FieldRanges.fieldTemp.min, max: FieldRanges.fieldTemp.max),
                const SizedBox(height: AppSpacing.lg),
                NumberField(label: l.fieldHumidity, controller: _c['fieldHumidity']!, unit: '%', min: FieldRanges.humidity.min, max: FieldRanges.humidity.max),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _text(String label, String key, int max) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(key: Key(key), controller: _c[key], maxLength: max, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(hintText: label, counterText: '')),
      ]);
}

// ───────────────────────── 2. Tag (FO-FR-05) ─────────────────────────

class _TagStep extends ConsumerStatefulWidget {
  const _TagStep({required this.draft, required this.save, required this.onDone});
  final WizardDraft draft;
  final Future<void> Function() save;
  final Future<void> Function() onDone;

  @override
  ConsumerState<_TagStep> createState() => _TagStepState();
}

class _TagStepState extends ConsumerState<_TagStep> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final d = widget.draft;
    return _StepScaffold(
      action: AppButton(
        key: const Key('tag-next'),
        label: l.next,
        busy: _busy,
        onPressed: d.tag == null
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  if (d.form['tagQueued'] != d.tag!.uid) {
                    await ref.read(operatorRepositoryProvider).attachTag(d.batchId!, d.tag!);
                    d.form['tagQueued'] = d.tag!.uid;
                  }
                  await widget.onDone();
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
      ),
      children: [
        Text(l.tagChoose, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.lg),
        TagPicker(
          current: d.tag,
          onRead: (t) async {
            setState(() => d.tag = t);
            await widget.save();
          },
        ),
      ],
    );
  }
}

// ───────────────────────── 3. Photos (FO-FR-06) ─────────────────────────

class _PhotosStep extends ConsumerStatefulWidget {
  const _PhotosStep({required this.draft, required this.save, required this.onDone});
  final WizardDraft draft;
  final Future<void> Function() save;
  final Future<void> Function() onDone;

  @override
  ConsumerState<_PhotosStep> createState() => _PhotosStepState();
}

class _PhotosStepState extends ConsumerState<_PhotosStep> {
  bool _busy = false;

  Future<void> _take(String view) async {
    final l = context.l10n;
    final (title, help) = switch (view) {
      'TOP' => (l.photoTop, l.photoHelpTop),
      'SIDE' => (l.photoSide, l.photoHelpSide),
      _ => (l.photoCloseup, l.photoHelpCloseup),
    };
    final shot = await ref.read(photoCaptureProvider)(context, title: title, instruction: help, fileStem: '${widget.draft.batchId}_$view');
    if (shot == null) return;
    setState(() {
      widget.draft.photos[view] = shot.path;
      widget.draft.form['photo.$view'] = {'size': shot.sizeBytes, 'w': shot.width, 'h': shot.height, 'orig': shot.originalPath, 'at': shot.capturedAt.toUtc().toIso8601String()};
    });
    await widget.save();
  }

  Future<void> _next() async {
    setState(() => _busy = true);
    final d = widget.draft;
    try {
      for (final v in _views) {
        final meta = Map<String, dynamic>.from(d.form['photo.$v'] as Map);
        if (meta['queued'] == true) continue;
        await ref.read(operatorRepositoryProvider).addPhoto(
              batchId: d.batchId!,
              view: v,
              localPath: d.photos[v]!,
              sizeBytes: meta['size'] as int,
              width: meta['w'] as int,
              height: meta['h'] as int,
              capturedAt: DateTime.parse(meta['at'] as String),
            );
        meta['queued'] = true;
        d.form['photo.$v'] = meta;
        await widget.save();
      }
      await widget.onDone();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final d = widget.draft;
    final all = _views.every((v) => d.photos[v] != null);
    final labels = {'TOP': l.photoTop, 'SIDE': l.photoSide, 'CLOSEUP': l.photoCloseup};
    return _StepScaffold(
      action: AppButton(key: const Key('photos-next'), label: l.next, busy: _busy, onPressed: all ? _next : null),
      children: [
        Text(l.photosNeeded, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.lg),
        for (final v in _views) ...[
          AppCard(
            status: d.photos[v] == null ? null : StatusLevel.safe,
            onTap: (d.form['photo.$v'] as Map?)?['queued'] == true ? null : () => _take(v),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.input),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: d.photos[v] == null
                      ? ColoredBox(color: context.palette.surfaceVariant, child: const Icon(Icons.photo_camera_rounded, size: 32))
                      : Image.file(File(d.photos[v]!), fit: BoxFit.cover, cacheWidth: 216, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_rounded)),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(labels[v]!, style: Theme.of(context).textTheme.titleMedium),
                  if (d.form['photo.$v'] is Map) Text('${((d.form['photo.$v'] as Map)['size'] as int) ~/ 1024} KB', style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
              Icon(d.photos[v] == null ? Icons.chevron_right_rounded : Icons.check_circle_rounded, color: d.photos[v] == null ? null : context.palette.safe),
            ]),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

// ───────────────────────── 4. Grade (FO-FR-07) ─────────────────────────

class _GradeStep extends ConsumerStatefulWidget {
  const _GradeStep({required this.draft, required this.save, required this.onDone});
  final WizardDraft draft;
  final Future<void> Function() save;
  final Future<void> Function() onDone;

  @override
  ConsumerState<_GradeStep> createState() => _GradeStepState();
}

class _GradeStepState extends ConsumerState<_GradeStep> {
  GradeResult? _result;
  String? _message;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    // After the first frame: _run reads the localisations, which initState may not (inherited widgets).
    if (widget.draft.grade == null && !widget.draft.gradeQueued) WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  /// Push the batch + photos, then grade (target: result within 5 s of upload, FO-FR-07).
  Future<void> _run() async {
    setState(() => _working = true);
    final repo = ref.read(operatorRepositoryProvider);
    final id = widget.draft.batchId!;
    final l = context.l10n;
    try {
      final scheduler = ref.read(syncSchedulerProvider);
      var synced = await repo.isSynced(id);
      for (var i = 0; i < 4 && !synced; i++) {
        await scheduler?.syncNow();
        synced = await repo.isSynced(id);
      }
      if (!synced) {
        await _queue(l.gradeQueued);
        return;
      }
      final r = await repo.grade(id);
      _result = r;
      widget.draft.grade = r.grade;
      await widget.save();
      unawaited(_dropOriginals()); // file cleanup; the result shows at once
    } on AppException catch (e) {
      await _queue(e.status == 503 ? l.gradeUnavailable : (e.isTransient ? l.gradeQueued : e.message));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _queue(String message) async {
    await ref.read(operatorRepositoryProvider).queueGrade(widget.draft.batchId!);
    widget.draft.gradeQueued = true;
    await widget.save();
    if (mounted) setState(() => _message = message);
  }

  /// Full-resolution originals are kept only until the batch is graded (FO-NFR-04).
  Future<void> _dropOriginals() async {
    for (final v in _views) {
      final orig = (widget.draft.form['photo.$v'] as Map?)?['orig'] as String?;
      if (orig != null) await File(orig).delete().catchError((_) => File(orig));
    }
  }

  Future<void> _dispute() async {
    final l = context.l10n;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.dispute),
        content: TextField(controller: reason, maxLines: 3, decoration: InputDecoration(hintText: l.disputeReason)),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)), FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l.send))],
      ),
    );
    if (ok != true || reason.text.trim().length < 3 || !mounted) return;
    try {
      await ref.read(operatorRepositoryProvider).dispute(widget.draft.batchId!, reason.text.trim());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.disputeSent)));
    } on AppException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.status == null ? l.onlineOnly : e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final r = _result;
    final grade = r?.grade ?? widget.draft.grade;
    return _StepScaffold(
      action: AppButton(key: const Key('grade-next'), label: l.next, onPressed: _working ? null : widget.onDone),
      secondary: r == null ? null : AppButton(label: l.dispute, kind: AppButtonKind.outlined, icon: Icons.flag_rounded, onPressed: _dispute),
      children: [
        if (_working) ...[
          const SizedBox(height: AppSpacing.xxl),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: AppSpacing.lg),
          Text(l.gradeWaiting, textAlign: TextAlign.center, style: t.titleMedium),
        ] else if (grade != null) ...[
          AppCard(
            status: GradeChip.levelOf(grade),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [GradeChip(grade: grade), const SizedBox(width: AppSpacing.md), Expanded(child: Text(l.gradeResult(grade), style: t.headlineSmall))]),
              if (r != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(l.confidence((r.confidence * 100).round()), style: t.bodyMedium),
                const SizedBox(height: AppSpacing.md),
                Text(l.defects, style: t.titleSmall),
                if (r.defects.isEmpty) Text(l.noDefects) else for (final dft in r.defects) Text('• ${dft['class']} (${(((dft['conf'] as num?) ?? 0) * 100).round()}%)'),
              ],
            ]),
          ),
        ] else
          AppCard(status: StatusLevel.watch, child: Row(children: [
            Icon(Icons.schedule_rounded, color: context.palette.watch),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(_message ?? l.gradeQueued, key: const Key('grade-queued'))),
          ])),
      ],
    );
  }
}

// ───────────────────────── 5. Storage (FO-FR-08) ─────────────────────────

class _StorageStep extends ConsumerStatefulWidget {
  const _StorageStep({required this.draft, required this.save, required this.onDone});
  final WizardDraft draft;
  final Future<void> Function() save;
  final Future<void> Function() onDone;

  @override
  ConsumerState<_StorageStep> createState() => _StorageStepState();
}

class _StorageStepState extends ConsumerState<_StorageStep> {
  late Future<StoragePath> _path = _load();
  bool _busy = false;

  Future<StoragePath> _load() async {
    final repo = ref.read(operatorRepositoryProvider);
    final id = widget.draft.batchId!;
    if (await repo.isSynced(id)) {
      try {
        return await repo.storagePath(id);
      } on AppException catch (e) {
        if (!e.isTransient) rethrow;
      }
    }
    // Offline: the same rule as the server, from the cached master lists.
    final m = await repo.masters(refresh: false);
    final product = m.product(widget.draft.form['productId'] as String)!;
    final session = ref.read(sessionProvider);
    final siteCode = session is SignedIn ? session.me.siteCode : null;
    final site = m.sites.where((s) => s.code == siteCode).firstOrNull;
    final units = m.units.where((u) => u.siteId == site?.id).toList();
    return localStoragePath(product, widget.draft.grade, units, double.tryParse('${widget.draft.form['weightKg']}') ?? 0);
  }

  Future<void> _assign(UnitOption u) async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      await ref.read(operatorRepositoryProvider).assignStorage(widget.draft.batchId!, u.id);
      widget.draft.storageUnitCode = u.code;
      await widget.save();
      // No snackbar: the card shows "Stored in …", and a snackbar would cover the Next button.
    } on AppException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.status == null ? l.onlineOnly : e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return FutureBuilder<StoragePath>(
      future: _path,
      builder: (context, snap) {
        final p = snap.data;
        return _StepScaffold(
          action: AppButton(key: const Key('storage-next'), label: l.next, onPressed: widget.onDone),
          secondary: p?.recommended == null || p!.offline || widget.draft.storageUnitCode != null
              ? null
              : AppButton(key: const Key('assign'), label: l.assign, kind: AppButtonKind.tonal, busy: _busy, onPressed: () => _assign(p.recommended!)),
          children: [
            if (snap.hasError)
              ErrorCard(error: snap.error!, onRetry: () => setState(() => _path = _load()))
            else if (p == null)
              const SkeletonList(rows: 2)
            else ...[
              AppCard(
                status: p.sellFirst ? StatusLevel.watch : StatusLevel.info,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(p.path == 'RIPENING_CHAMBER' ? Icons.eco_rounded : Icons.ac_unit_rounded, size: 32),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: Text(storagePathText(l, p.path), key: const Key('storage-path'), style: t.headlineSmall)),
                  ]),
                  if (p.sellFirst) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: StatusChip(level: StatusLevel.watch, label: l.sellFirst)),
                  const SizedBox(height: AppSpacing.md),
                  Text(p.recommended == null ? l.noUnit : l.recommendedUnit(p.recommended!.code, p.recommended!.freeKg.toStringAsFixed(0)), style: t.titleMedium),
                  if (widget.draft.storageUnitCode != null) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: StatusChip(level: StatusLevel.safe, label: l.assigned(widget.draft.storageUnitCode!))),
                  if (p.offline) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Text(l.storageOffline, style: t.bodySmall)),
                ]),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ───────────────────────── 6. Label (FO-FR-09) ─────────────────────────

class _LabelStep extends ConsumerStatefulWidget {
  const _LabelStep({required this.draft, required this.onDone});
  final WizardDraft draft;
  final Future<void> Function() onDone;

  @override
  ConsumerState<_LabelStep> createState() => _LabelStepState();
}

class _LabelStepState extends ConsumerState<_LabelStep> {
  late final Future<LabelData?> _label = _load();

  Future<LabelData?> _load() async {
    final repo = ref.read(operatorRepositoryProvider);
    if (!await repo.isSynced(widget.draft.batchId!)) return null;
    try {
      return await repo.label(widget.draft.batchId!);
    } on AppException catch (e) {
      if (e.isTransient) return null;
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return FutureBuilder<LabelData?>(
      future: _label,
      builder: (context, snap) => _StepScaffold(
        action: AppButton(key: const Key('label-next'), label: l.next, onPressed: widget.onDone),
        children: [
          if (snap.connectionState != ConnectionState.done)
            const SkeletonList(rows: 3)
          else if (snap.hasError)
            ErrorCard(error: snap.error!)
          else if (snap.data == null)
            AppCard(status: StatusLevel.info, child: Text(l.labelOffline, key: const Key('label-offline')))
          else
            LabelActions(data: snap.data!),
        ],
      ),
    );
  }
}

// ───────────────────────── 7. Done (FO-NFR-03) ─────────────────────────

class _DoneStep extends ConsumerStatefulWidget {
  const _DoneStep({required this.draft});
  final WizardDraft draft;

  @override
  ConsumerState<_DoneStep> createState() => _DoneStepState();
}

class _DoneStepState extends ConsumerState<_DoneStep> {
  late final int _seconds = DateTime.now().difference(widget.draft.startedAt ?? DateTime.now()).inSeconds;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(databaseProvider)!.clearDraft().then((_) => ref.invalidate(operatorDraftProvider)));
    ref.invalidate(summaryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return _StepScaffold(
      action: AppButton(key: const Key('done-new'), label: l.newBatch, icon: Icons.add_rounded, onPressed: () => context.pushReplacement('/batch/new/${widget.draft.category.toLowerCase()}')),
      secondary: AppButton(label: l.goHome, kind: AppButtonKind.outlined, onPressed: () => context.go('/home')),
      children: [
        const SizedBox(height: AppSpacing.xl),
        Icon(Icons.check_circle_rounded, size: 72, color: context.palette.safe),
        const SizedBox(height: AppSpacing.lg),
        Text(l.doneTitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        Text(l.doneTime(_seconds), key: const Key('done-time'), textAlign: TextAlign.center),
        if (widget.draft.gradeQueued) Padding(padding: const EdgeInsets.only(top: AppSpacing.md), child: Text(l.gradeQueued, textAlign: TextAlign.center)),
      ],
    );
  }
}
