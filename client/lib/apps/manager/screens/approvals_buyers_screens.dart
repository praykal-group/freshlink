import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/status.dart';
import '../data/models.dart';
import '../providers.dart';
import '../widgets/manager_widgets.dart';

final editRequestsProvider = FutureProvider.autoDispose<ApiPage>((ref) => ref.watch(managerRepositoryProvider).editRequests());
final disputesProvider = FutureProvider.autoDispose<ApiPage>((ref) => ref.watch(managerRepositoryProvider).disputes());

/// Section 10.6 #6: batch edit requests (after the 30-min window) and grade disputes.
class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.read(managerRepositoryProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: Text(l.mgrApprovals), bottom: TabBar(tabs: [Tab(text: l.editRequestsTab), Tab(key: const Key('tab-disputes'), text: l.disputesTab)])),
        body: TabBarView(children: [
          AsyncView<ApiPage>(
            value: ref.watch(editRequestsProvider),
            onRetry: () => ref.invalidate(editRequestsProvider),
            isEmpty: (p) => p.items.isEmpty,
            empty: EmptyState(title: l.nothingPending, icon: Icons.done_all_rounded),
            data: (p) => ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
              for (final r in p.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AppCard(
                    key: Key('edit-${r['id']}'),
                    status: StatusLevel.watch,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${map(r['batch'])['code'] ?? ''}', style: Theme.of(context).textTheme.titleSmall),
                      Text(l.requestedBy('${map(r['requester'])['name'] ?? ''}', dateTimeText(context, date(r['createdAt'])))),
                      const SizedBox(height: AppSpacing.xs),
                      for (final e in map(r['changes']).entries) Text('• ${e.key}: ${e.value}'),
                      Text(l.reasonIs('${r['reason']}')),
                      Wrap(alignment: WrapAlignment.end, spacing: AppSpacing.sm, children: [
                        TextButton(
                          key: Key('reject-${r['id']}'),
                          onPressed: () async {
                            if (await runAndReport(context, () => repo.decideEdit('${r['id']}', false), success: l.rejected)) ref.invalidate(editRequestsProvider);
                          },
                          child: Text(l.reject),
                        ),
                        FilledButton(
                          key: Key('approve-${r['id']}'),
                          onPressed: () async {
                            if (await runAndReport(context, () => repo.decideEdit('${r['id']}', true), success: l.approved)) ref.invalidate(editRequestsProvider);
                          },
                          child: Text(l.approve),
                        ),
                      ]),
                    ]),
                  ),
                ),
            ]),
          ),
          AsyncView<ApiPage>(
            value: ref.watch(disputesProvider),
            onRetry: () => ref.invalidate(disputesProvider),
            isEmpty: (p) => p.items.isEmpty,
            empty: EmptyState(title: l.nothingPending, icon: Icons.done_all_rounded),
            data: (p) => ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
              for (final g in p.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AppCard(
                    key: Key('dispute-${g['id']}'),
                    status: StatusLevel.watch,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      TitleChip(title: '${map(g['batch'])['code'] ?? ''}', chip: GradeChip(grade: '${g['grade']}')),
                      Text(l.operatorSays('${g['disputeReason'] ?? ''}')),
                      if (g['confidence'] != null) Text(l.aiConfidence((num0(g['confidence'])! * 100).round())),
                      const SizedBox(height: AppSpacing.xs),
                      Text(l.setGrade, style: Theme.of(context).textTheme.labelMedium),
                      Wrap(spacing: AppSpacing.sm, children: [
                        for (final grade in const ['A', 'B', 'C'])
                          OutlinedButton(
                            key: Key('grade-${g['id']}-$grade'),
                            onPressed: () async {
                              if (await runAndReport(context, () => repo.resolveDispute('${g['id']}', grade), success: l.gradeSet(grade))) ref.invalidate(disputesProvider);
                            },
                            child: Text(grade),
                          ),
                      ]),
                    ]),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

final buyersProvider = FutureProvider.autoDispose<ApiPage>((ref) => ref.watch(managerRepositoryProvider).buyers());

const buyerTypes = ['CANNING', 'PROCESSING', 'LOCAL_MARKET', 'DISCOUNT_RETAIL', 'COLD_STORAGE'];

/// Section 10.6 #7: backup buyers and cold storages.
class BuyersScreen extends ConsumerWidget {
  const BuyersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    Future<void> open([Map<String, dynamic>? b]) async {
      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => BuyerFormScreen(buyer: b)));
      if (saved == true) ref.invalidate(buyersProvider);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.mgrBuyers)),
      floatingActionButton: FloatingActionButton.extended(key: const Key('buyer-add'), onPressed: open, icon: const Icon(Icons.add_rounded), label: Text(l.addBuyer)),
      body: AsyncView<ApiPage>(
        value: ref.watch(buyersProvider),
        onRetry: () => ref.invalidate(buyersProvider),
        isEmpty: (p) => p.items.isEmpty,
        empty: EmptyState(title: l.noBuyers, icon: Icons.storefront_rounded),
        data: (p) => ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)).copyWith(bottom: 96), children: [
          for (final b in p.items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                key: Key('buyer-${b['name']}'),
                onTap: () => open(b),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${b['name']}', style: Theme.of(context).textTheme.titleSmall),
                  Text('${b['type']} · ${l.minGradeIs('${b['minGrade']}')} · −${num0(b['discountPct'])?.toStringAsFixed(0) ?? 0} %'),
                  Text(l.acceptsProducts((b['acceptedProductIds'] as List? ?? const []).length)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Create / edit a buyer: details, product multi-select, opening-hours editor (W-1).
class BuyerFormScreen extends ConsumerStatefulWidget {
  const BuyerFormScreen({super.key, this.buyer});
  final Map<String, dynamic>? buyer;

  @override
  ConsumerState<BuyerFormScreen> createState() => _BuyerFormScreenState();
}

class _BuyerFormScreenState extends ConsumerState<BuyerFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.buyer?['name'] as String?);
  late final _phone = TextEditingController(text: widget.buyer?['phone'] as String? ?? '+91');
  late final _email = TextEditingController(text: widget.buyer?['email'] as String?);
  late final _lat = TextEditingController(text: '${widget.buyer?['lat'] ?? ''}');
  late final _lng = TextEditingController(text: '${widget.buyer?['lng'] ?? ''}');
  late final _discount = TextEditingController(text: num0(widget.buyer?['discountPct'])?.toStringAsFixed(0) ?? '20');
  late final _capacity = TextEditingController(text: widget.buyer?['capacityKg'] == null ? '' : '${num0(widget.buyer!['capacityKg'])!.round()}');
  late String _type = widget.buyer?['type'] as String? ?? 'LOCAL_MARKET';
  late String _minGrade = widget.buyer?['minGrade'] as String? ?? 'B';
  late final Set<String> _products = {...((widget.buyer?['acceptedProductIds'] as List?) ?? const []).cast<String>()};
  late OpeningHours _hours = widget.buyer == null ? OpeningHours.everyDay('06:00', '20:00') : OpeningHours.fromJson(widget.buyer!['openingHours']);
  String? _hoursError;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _lat, _lng, _discount, _capacity]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) => (v ?? '').trim().isEmpty ? context.l10n.fieldRequired : null;
  String? _number(String? v, double min, double max) {
    final n = double.tryParse((v ?? '').trim());
    return n == null || n < min || n > max ? context.l10n.numberBetween('$min', '$max') : null;
  }

  Future<void> _save() async {
    final l = context.l10n;
    final bad = _hours.invalidDay();
    setState(() => _hoursError = bad == null ? null : l.hoursInvalid(bad));
    if (!_form.currentState!.validate() || bad != null) return;
    if (_products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.pickOneProduct)));
      return;
    }
    final body = {
      'name': _name.text.trim(),
      'type': _type,
      'phone': _phone.text.trim(),
      if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
      'lat': double.parse(_lat.text.trim()),
      'lng': double.parse(_lng.text.trim()),
      'acceptedProductIds': _products.toList(),
      'minGrade': _minGrade,
      'discountPct': double.parse(_discount.text.trim()),
      'openingHours': _hours.toJson(),
      if (_capacity.text.trim().isNotEmpty) 'capacityKg': double.parse(_capacity.text.trim()),
    };
    setState(() => _busy = true);
    final ok = await runAndReport(context, () => ref.read(managerRepositoryProvider).saveBuyer(widget.buyer?['id'] as String?, body), success: l.saved);
    if (mounted) setState(() => _busy = false);
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _editDay(String day) async {
    final cur = _hours.days[day] ?? const [];
    final l = context.l10n;
    final r = await showDialog<Map<String, String>>(
      context: context,
      builder: (c) => TextFieldsDialog(
        title: l.hoursFor(day),
        saveLabel: l.save,
        extraLabel: l.closedDay,
        extraValue: const {'closed': '1'},
        fields: [
          DialogField('hours-open', l.opens, initial: cur.isEmpty ? '06:00' : cur.first.$1, hint: 'HH:MM'),
          DialogField('hours-close', l.closes, initial: cur.isEmpty ? '20:00' : cur.first.$2, hint: 'HH:MM'),
        ],
      ),
    );
    if (r == null) return;
    setState(() => _hours = OpeningHours({..._hours.days, day: r.containsKey('closed') ? const [] : [(r['hours-open']!.trim(), r['hours-close']!.trim())]}));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final products = ref.watch(productsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.buyer == null ? l.addBuyer : l.editBuyer), actions: [
        if (widget.buyer != null)
          IconButton(
            key: const Key('buyer-delete'),
            tooltip: l.deactivate,
            onPressed: () async {
              if (await confirm(context, l.deactivateBuyer, danger: true) && context.mounted && await runAndReport(context, () => ref.read(managerRepositoryProvider).deleteBuyer('${widget.buyer!['id']}')) && context.mounted) Navigator.pop(context, true);
            },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
      ]),
      body: Form(
        key: _form,
        child: ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
          TextFormField(key: const Key('buyer-name'), controller: _name, decoration: InputDecoration(labelText: l.name), validator: _required),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: const Key('buyer-type'),
            initialValue: _type,
            decoration: InputDecoration(labelText: l.typeLabel),
            items: [for (final t in buyerTypes) DropdownMenuItem(value: t, child: Text(t))],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const Key('buyer-phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: l.phoneE164),
            validator: (v) => RegExp(r'^\+[1-9]\d{7,14}$').hasMatch((v ?? '').trim()) ? null : l.phoneInvalidE164,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: l.emailOptional)),
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Expanded(child: TextFormField(key: const Key('buyer-lat'), controller: _lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: InputDecoration(labelText: l.latitude), validator: (v) => _number(v, -90, 90))),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: TextFormField(key: const Key('buyer-lng'), controller: _lng, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: InputDecoration(labelText: l.longitude), validator: (v) => _number(v, -180, 180))),
          ]),
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Expanded(child: TextFormField(key: const Key('buyer-discount'), controller: _discount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l.discountPct, suffixText: '%'), validator: (v) => _number(v, 0, 100))),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _minGrade,
                decoration: InputDecoration(labelText: l.minGrade),
                items: [for (final g in const ['A', 'B', 'C']) DropdownMenuItem(value: g, child: Text(g))],
                onChanged: (v) => setState(() => _minGrade = v ?? _minGrade),
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.md),
          TextFormField(controller: _capacity, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l.capacityOptional, suffixText: 'kg'), validator: (v) => (v ?? '').trim().isEmpty ? null : _number(v, 1, 1e7)),
          const SizedBox(height: AppSpacing.lg),
          Text(l.acceptedProducts, style: Theme.of(context).textTheme.titleSmall),
          Wrap(spacing: AppSpacing.sm, children: [
            for (final p in products)
              FilterChip(
                key: Key('buyer-product-${p['code']}'),
                label: Text(localName(p, lang)),
                selected: _products.contains(p['id']),
                onSelected: (on) => setState(() => on ? _products.add('${p['id']}') : _products.remove(p['id'])),
              ),
          ]),
          const SizedBox(height: AppSpacing.lg),
          Text(l.openingHours, style: Theme.of(context).textTheme.titleSmall),
          for (final d in OpeningHours.keys)
            ListTile(
              key: Key('hours-$d'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(d.toUpperCase()),
              trailing: Text((_hours.days[d] ?? const []).isEmpty ? l.closedDay : (_hours.days[d]!).map((r) => '${r.$1}–${r.$2}').join(', ')),
              onTap: () => _editDay(d),
            ),
          if (_hoursError != null) Text(_hoursError!, key: const Key('hours-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: AppSpacing.xl),
          AppButton(key: const Key('buyer-save'), label: l.save, icon: Icons.save_rounded, busy: _busy, onPressed: _busy ? null : _save),
        ]),
      ),
    );
  }
}
