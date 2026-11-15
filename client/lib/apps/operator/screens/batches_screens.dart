import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_exception.dart';
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
import '../widgets/operator_widgets.dart';

const _statuses = ['REGISTERED', 'GRADED', 'STORED', 'ALLOCATED', 'LOADED', 'IN_TRANSIT', 'DELIVERED', 'REJECTED'];

/// Batch list (FO-FR-12): status chips, search by code or tag UID, infinite scroll; batches
/// registered on this phone and not yet synced appear first, marked "Not synced yet".
class BatchListScreen extends ConsumerStatefulWidget {
  const BatchListScreen({super.key});

  @override
  ConsumerState<BatchListScreen> createState() => _BatchListScreenState();
}

class _BatchListScreenState extends ConsumerState<BatchListScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String? _status;
  List<BatchItem> _items = [];
  String? _cursor;
  bool _loading = false;
  bool _done = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _reload();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _more();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _items = [];
      _cursor = null;
      _done = false;
      _error = null;
    });
    await _more();
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    setState(() => _loading = true);
    try {
      final page = await ref.read(operatorRepositoryProvider).list(status: _status, q: _search.text.trim(), cursor: _cursor);
      setState(() {
        _items = [..._items, ...page.items];
        _cursor = page.nextCursor;
        _done = page.nextCursor == null;
      });
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    ref.listen(batchRefreshProvider, (_, _) => _reload());
    final value = _error != null && _items.isEmpty ? AsyncValue<List<BatchItem>>.error(_error!, StackTrace.empty) : (_loading && _items.isEmpty ? const AsyncValue<List<BatchItem>>.loading() : AsyncValue.data(_items));
    return Scaffold(
      appBar: AppBar(title: Text(l.batches)),
      body: Column(children: [
        const OfflineBanner(),
        Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.screenPadding(context), AppSpacing.sm, AppSpacing.screenPadding(context), 0),
          child: TextField(
            key: const Key('batch-search'),
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _reload(),
            decoration: InputDecoration(hintText: l.searchBatches, prefixIcon: const Icon(Icons.search_rounded), suffixIcon: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () {
              _search.clear();
              _reload();
            })),
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm), children: [
            ChoiceChip(label: Text(l.all), selected: _status == null, onSelected: (_) {
              _status = null;
              _reload();
            }),
            for (final s in _statuses) ...[
              const SizedBox(width: AppSpacing.sm),
              ChoiceChip(label: Text(batchStatusText(l, s)), selected: _status == s, onSelected: (_) {
                _status = s;
                _reload();
              }),
            ],
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: AsyncView<List<BatchItem>>(
              value: value,
              onRetry: _reload,
              isEmpty: (x) => x.isEmpty,
              data: (items) => ListView.separated(
                controller: _scroll,
                padding: EdgeInsets.all(AppSpacing.screenPadding(context)),
                itemCount: items.length + (_done ? 0 : 1),
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (_, i) => i >= items.length ? const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: CircularProgressIndicator())) : _BatchTile(b: items[i]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _BatchTile extends ConsumerWidget {
  const _BatchTile({required this.b});
  final BatchItem b;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final masters = ref.watch(mastersProvider).value;
    final lang = ref.watch(localeProvider).languageCode;
    final name = masters?.product(b.productId)?.localName(lang) ?? b.productName ?? '';
    return AppCard(
      status: b.pending ? StatusLevel.watch : batchStatusLevel(b.status),
      onTap: b.pending ? null : () => context.push('/batches/${b.id}'),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(b.displayCode, style: t.titleSmall),
            Text('$name · ${b.weightKg.toStringAsFixed(1)} kg', style: t.bodyMedium),
            const SizedBox(height: AppSpacing.xs),
            Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
              if (b.pending) StatusChip(level: StatusLevel.watch, label: l.pendingSync) else StatusChip(level: batchStatusLevel(b.status), label: batchStatusText(l, b.status)),
              if (b.grade != null) GradeChip(grade: b.grade!),
            ]),
          ]),
        ),
        if (!b.pending) const Icon(Icons.chevron_right_rounded),
      ]),
    );
  }
}

final _detailProvider = FutureProvider.autoDispose.family<(Map<String, dynamic>, Map<String, dynamic>), String>((ref, id) async {
  final repo = ref.watch(operatorRepositoryProvider);
  final results = await Future.wait([repo.detail(id), repo.timeline(id)]);
  return (results[0], results[1]);
});

/// Batch detail (Section 10.4 #4): grade, shelf life, storage, tags, hash-chained history; Edit
/// within 30 min (FO-FR-13) or Request edit; reprint the label.
class BatchDetailScreen extends ConsumerWidget {
  const BatchDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final v = ref.watch(_detailProvider(id));
    return Scaffold(
      appBar: AppBar(title: Text(v.value?.$1['code'] as String? ?? l.batches)),
      body: AsyncView<(Map<String, dynamic>, Map<String, dynamic>)>(
        value: v,
        onRetry: () => ref.invalidate(_detailProvider(id)),
        data: (d) => _Detail(id: id, batch: d.$1, timeline: d.$2),
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.id, required this.batch, required this.timeline});
  final String id;
  final Map<String, dynamic> batch;
  final Map<String, dynamic> timeline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final item = BatchItem.fromJson(batch);
    final lang = ref.watch(localeProvider).languageCode;
    final product = batch['product'] as Map?;
    final name = switch (lang) { 'hi' => product?['nameHi'], 'mr' => product?['nameMr'], _ => product?['name'] } as String? ?? '';
    final minutesLeft = 30 - DateTime.now().difference(item.createdAt).inMinutes;
    final fmt = DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).add_Hm();
    final events = (timeline['events'] as List? ?? const []).cast<Map>();
    return ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
      AppCard(
        status: batchStatusLevel(item.status),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: t.titleLarge),
          Text('${item.weightKg.toStringAsFixed(1)} kg · ${fmt.format(item.caughtOrHarvestedAt.toLocal())}', style: t.bodyMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
            StatusChip(level: batchStatusLevel(item.status), label: batchStatusText(l, item.status)),
            if (item.grade != null) GradeChip(grade: item.grade!),
            if (item.remainingShelfLifeH != null) StatusChip(level: item.remainingShelfLifeH! < 12 ? StatusLevel.critical : StatusLevel.info, label: l.shelfLifeHours(item.remainingShelfLifeH!.toStringAsFixed(0))),
            if (batch['storageUnit'] != null) StatusChip(level: StatusLevel.safe, label: l.assigned((batch['storageUnit'] as Map)['code'] as String)),
          ]),
          if ((batch['tags'] as List?)?.isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('${l.tags}: ${(batch['tags'] as List).map((x) => '${x['tagType']} ${x['tagUid']}').join(', ')}', style: t.bodySmall),
          ],
        ]),
      ),
      const SizedBox(height: AppSpacing.md),
      if (minutesLeft > 0) ...[
        AppButton(key: const Key('edit'), label: '${l.edit} · ${l.editMinutesLeft(minutesLeft)}', icon: Icons.edit_rounded, kind: AppButtonKind.tonal, onPressed: () => _edit(context, ref, item, direct: true)),
      ] else ...[
        Text(l.editClosed, style: t.bodySmall),
        const SizedBox(height: AppSpacing.sm),
        AppButton(key: const Key('request-edit'), label: l.requestEdit, icon: Icons.edit_note_rounded, kind: AppButtonKind.outlined, onPressed: () => _edit(context, ref, item, direct: false)),
      ],
      const SizedBox(height: AppSpacing.md),
      AppButton(
        label: l.printLabel,
        icon: Icons.qr_code_2_rounded,
        kind: AppButtonKind.outlined,
        onPressed: () async {
          try {
            final label = await ref.read(operatorRepositoryProvider).label(id);
            if (!context.mounted) return;
            await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(AppSpacing.lg), child: LabelActions(data: label))));
          } on AppException catch (e) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.status == null ? l.onlineOnly : e.message)));
          }
        },
      ),
      const SizedBox(height: AppSpacing.xl),
      Row(children: [
        Expanded(child: Text(l.history, style: t.titleMedium)),
        StatusChip(level: timeline['verified'] == true ? StatusLevel.safe : StatusLevel.critical, label: timeline['verified'] == true ? l.chainVerified : l.chainBroken),
      ]),
      const SizedBox(height: AppSpacing.sm),
      for (final e in events)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 14, backgroundColor: context.palette.primaryContainer, child: Text('${e['seq']}', style: t.labelSmall)),
          title: Text('${e['type']}'.replaceAll('_', ' ')),
          subtitle: Text(fmt.format(DateTime.parse(e['occurredAt'] as String).toLocal())),
        ),
    ]);
  }

  /// FO-FR-13: within 30 min a queued correction; later a reasoned request to the manager.
  Future<void> _edit(BuildContext context, WidgetRef ref, BatchItem item, {required bool direct}) async {
    final l = context.l10n;
    final weight = TextEditingController(text: item.weightKg.toString());
    final reason = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, MediaQuery.viewInsetsOf(c).bottom + AppSpacing.lg),
        child: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(direct ? l.edit : l.requestEdit, style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            NumberField(fieldKey: const Key('edit-weight'), label: l.weight, controller: weight, unit: 'kg', min: 0.1, max: 50000, required: true),
            if (!direct) ...[
              const SizedBox(height: AppSpacing.md),
              TextFormField(controller: reason, maxLines: 2, decoration: InputDecoration(hintText: l.reason), validator: (v) => (v ?? '').trim().length < 3 ? l.errorRequired : null),
            ],
            const SizedBox(height: AppSpacing.lg),
            AppButton(label: direct ? l.ok : l.send, onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(c, true);
            }),
          ]),
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final changes = {'weightKg': double.parse(weight.text.replaceAll(',', '.'))};
    final repo = ref.read(operatorRepositoryProvider);
    try {
      if (direct) {
        await repo.update(item.id, changes);
        await ref.read(syncSchedulerProvider)?.syncNow();
      } else {
        await repo.requestEdit(item.id, changes, reason.text.trim());
      }
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(direct ? l.saved : l.requestSent)));
      ref.invalidate(_detailProvider(item.id));
    } on AppException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.status == null ? l.onlineOnly : e.message)));
    }
  }
}
