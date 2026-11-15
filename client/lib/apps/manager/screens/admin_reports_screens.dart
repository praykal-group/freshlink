import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/save_file.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/status.dart';
import '../data/models.dart';
import '../providers.dart';
import '../widgets/manager_widgets.dart';

// ───────────── Reports (Section 10.6 #10) ─────────────

final reeferHealthProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.watch(managerRepositoryProvider).reeferHealth());

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final _batch = TextEditingController();
  DateTimeRange _range = DateTimeRange(start: DateTime.now().subtract(const Duration(days: 30)), end: DateTime.now());
  List<Map<String, dynamic>> _found = const [];
  Map<String, dynamic>? _emissions;

  @override
  void dispose() {
    _batch.dispose();
    super.dispose();
  }

  String get _from => ymd(_range.start);
  String get _to => ymd(_range.end);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final repo = ref.read(managerRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.mgrReports)),
      body: ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
        Section(
          title: l.complianceReport,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: TextField(key: const Key('rep-batch'), controller: _batch, decoration: InputDecoration(labelText: l.batchCodeOrTag))),
              IconButton(
                key: const Key('rep-find'),
                tooltip: l.search,
                onPressed: () async {
                  final q = _batch.text.trim();
                  if (q.length < 3) return;
                  await runAndReport(context, () async {
                    final p = await repo.findBatches(q);
                    setState(() => _found = p.items);
                  });
                },
                icon: const Icon(Icons.search_rounded),
              ),
            ]),
            for (final b in _found)
              ListTile(
                key: Key('rep-batch-${b['code']}'),
                contentPadding: EdgeInsets.zero,
                title: Text('${b['code']}'),
                subtitle: Text('${b['status']}'),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () => runAndReport(context, () async => saveOrShareFile(name: 'compliance-${b['code']}.html', mime: 'text/html', text: await repo.complianceHtml('${b['id']}'))),
              ),
          ]),
        ),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpacing.sm, children: [
          Text(l.periodIs(_from, _to)),
          TextButton(
            key: const Key('rep-range'),
            onPressed: () async {
              final r = await showDateRangePicker(context: context, firstDate: DateTime(2025), lastDate: DateTime.now(), initialDateRange: _range);
              if (r != null) setState(() => _range = r);
            },
            child: Text(l.changeDate),
          ),
        ]),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const Key('rep-trace'),
          label: l.traceabilityCsv,
          icon: Icons.download_rounded,
          kind: AppButtonKind.outlined,
          onPressed: () => runAndReport(context, () async => saveOrShareFile(name: 'traceability-$_from-$_to.csv', mime: 'text/csv', text: await repo.traceabilityCsv(_from, _to))),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const Key('rep-emissions'),
          label: l.emissionsReport,
          icon: Icons.co2_rounded,
          kind: AppButtonKind.outlined,
          onPressed: () => runAndReport(context, () async {
            final e = await repo.emissions(_from, _to);
            setState(() => _emissions = e);
          }),
        ),
        if (_emissions != null) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            key: const Key('emissions-card'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.emissionsTotals((map(_emissions!['totals'])['trips'] as num? ?? 0).toInt(), '${num0(map(_emissions!['totals'])['distanceKm'])?.toStringAsFixed(1) ?? 0}', '${num0(map(_emissions!['totals'])['co2Kg'])?.toStringAsFixed(1) ?? 0}')),
              Text(l.emissionFactor('${map(_emissions!['currentFactor'])['value'] ?? '–'}', '${map(_emissions!['currentFactor'])['source'] ?? ''}'), style: Theme.of(context).textTheme.bodySmall),
              TextButton(onPressed: () => runAndReport(context, () async => saveOrShareFile(name: 'emissions-$_from-$_to.csv', mime: 'text/csv', text: await repo.emissionsCsv(_from, _to))), child: Text(l.downloadCsv)),
            ]),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Section(
          title: l.reeferHealth,
          child: AsyncView<List<Map<String, dynamic>>>(
            value: ref.watch(reeferHealthProvider),
            onRetry: () => ref.invalidate(reeferHealthProvider),
            skeleton: const SkeletonList(rows: 2),
            isEmpty: (v) => v.isEmpty,
            empty: EmptyState(title: l.noData),
            data: (rows) {
              return Column(children: [
                for (final v in rows)
                  ListTile(
                    key: Key('reefer-${v['regNo']}'),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(v['flagged'] == true ? Icons.warning_amber_rounded : Icons.check_circle_rounded),
                    title: Text('${v['regNo']}'),
                    // the chip sits under the text: as a trailing widget it filled the tile at text scale 2.0
                    subtitle: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(maps(v['weeks']).isEmpty ? l.noWeeks : l.degradation('${maps(v['weeks']).first['degradationPct']}')),
                      if (v['flagged'] == true) StatusChip(level: StatusLevel.watch, label: l.flagged),
                    ]),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

// ───────────── App releases (Section 10.6 #11) ─────────────

final releasesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.watch(managerRepositoryProvider).releases());

class ReleasesScreen extends ConsumerWidget {
  const ReleasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.mgrReleases)),
      body: AsyncView<List<Map<String, dynamic>>>(
        value: ref.watch(releasesProvider),
        onRetry: () => ref.invalidate(releasesProvider),
        isEmpty: (v) => v.isEmpty,
        empty: EmptyState(title: l.noReleases, message: l.noReleasesHint, icon: Icons.system_update_rounded),
        data: (v) => ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
          for (final r in v)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                status: r['mandatory'] == true ? StatusLevel.watch : null,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r['flavor']} ${r['versionName']} (${r['versionCode']}) · ${r['channel']}', style: Theme.of(context).textTheme.titleSmall),
                  Text('${dateTimeText(context, date(r['publishedAt']))} · ${((num0(r['sizeBytes']) ?? 0) / 1048576).toStringAsFixed(1)} MB${r['mandatory'] == true ? ' · ${l.mandatory}' : ''}'),
                  for (final f in (r['features'] as List? ?? const [])) Text('• $f'),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

// ───────────── Masters (ADMIN, Section 10.6 #8) ─────────────

enum FieldKind { text, number, boolean, choice, site, vehicle, storageUnit, secret }

/// One editable column of a master entity. [createOnly] fields (codes, reg no) are immutable
/// after create, as the API's Update DTOs omit them.
class FieldSpec {
  const FieldSpec(this.key, this.kind, {this.options = const [], this.required = true, this.createOnly = false});
  final String key;
  final FieldKind kind;
  final List<String> options;
  final bool required;
  final bool createOnly;
}

const masterSpecs = <String, List<FieldSpec>>{
  'products': [
    FieldSpec('code', FieldKind.text, createOnly: true), FieldSpec('name', FieldKind.text), FieldSpec('nameHi', FieldKind.text), FieldSpec('nameMr', FieldKind.text),
    FieldSpec('category', FieldKind.choice, options: ['FISH', 'PRODUCE']), FieldSpec('isClimacteric', FieldKind.boolean), FieldSpec('isEthyleneSensitive', FieldKind.boolean),
    FieldSpec('safeTempMin', FieldKind.number), FieldSpec('safeTempMax', FieldKind.number), FieldSpec('humidityMin', FieldKind.number), FieldSpec('humidityMax', FieldKind.number),
    FieldSpec('ethyleneMaxPpm', FieldKind.number, required: false), FieldSpec('shockMaxG', FieldKind.number), FieldSpec('baseShelfLifeH', FieldKind.number), FieldSpec('q10', FieldKind.number),
    FieldSpec('unitPrice', FieldKind.number), FieldSpec('active', FieldKind.boolean, required: false),
  ],
  'sites': [
    FieldSpec('code', FieldKind.text, createOnly: true), FieldSpec('name', FieldKind.text), FieldSpec('type', FieldKind.choice, options: ['DOCK', 'FARM_GATE', 'COLD_STORAGE', 'WAREHOUSE', 'DISTRIBUTION_CENTRE']),
    FieldSpec('lat', FieldKind.number), FieldSpec('lng', FieldKind.number), FieldSpec('address', FieldKind.text, required: false), FieldSpec('active', FieldKind.boolean, required: false),
  ],
  'storage-units': [
    FieldSpec('siteId', FieldKind.site, createOnly: true), FieldSpec('code', FieldKind.text, createOnly: true), FieldSpec('type', FieldKind.choice, options: ['BLAST_CHILLER', 'RIPENING_CHAMBER', 'COLD_ROOM']),
    FieldSpec('tempMin', FieldKind.number), FieldSpec('tempMax', FieldKind.number), FieldSpec('capacityKg', FieldKind.number), FieldSpec('active', FieldKind.boolean, required: false),
  ],
  'vehicles': [
    FieldSpec('regNo', FieldKind.text, createOnly: true), FieldSpec('capacityKg', FieldKind.number), FieldSpec('reeferMinTemp', FieldKind.number), FieldSpec('reeferMaxTemp', FieldKind.number),
    FieldSpec('homeSiteId', FieldKind.site), FieldSpec('status', FieldKind.choice, options: ['AVAILABLE', 'IN_USE', 'MAINTENANCE', 'INACTIVE'], required: false),
  ],
  'devices': [
    FieldSpec('deviceCode', FieldKind.text, createOnly: true), FieldSpec('vehicleId', FieldKind.vehicle, required: false), FieldSpec('storageUnitId', FieldKind.storageUnit, required: false),
    FieldSpec('secret', FieldKind.secret), FieldSpec('status', FieldKind.choice, options: ['ACTIVE', 'INACTIVE', 'FAULTY'], required: false),
  ],
};

/// The body for create / update from the form values: numbers parsed, create-only fields and an
/// empty write-only secret left out on update, empty optional fields left out.
Map<String, dynamic> masterBody(List<FieldSpec> specs, Map<String, Object?> values, {required bool create}) => {
      for (final f in specs)
        if ((create || !f.createOnly) && !(f.kind == FieldKind.secret && !create && '${values[f.key] ?? ''}'.isEmpty))
          if (values[f.key] case final v? when '$v'.trim().isNotEmpty) f.key: f.kind == FieldKind.number ? double.parse('$v'.trim().replaceAll(',', '.')) : v,
    };

String rowTitle(String entity, Map<String, dynamic> r) => '${r['code'] ?? r['regNo'] ?? r['deviceCode'] ?? r['name'] ?? r['id']}';

final masterListProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, e) => ref.watch(managerRepositoryProvider).masterList(e));

class MastersScreen extends ConsumerStatefulWidget {
  const MastersScreen({super.key});

  @override
  ConsumerState<MastersScreen> createState() => _MastersScreenState();
}

class _MastersScreenState extends ConsumerState<MastersScreen> {
  String _entity = 'products';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final rows = ref.watch(masterListProvider(_entity));
    Future<void> open([Map<String, dynamic>? row]) async {
      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => MasterFormScreen(entity: _entity, row: row)));
      if (saved == true) {
        ref.invalidate(masterListProvider(_entity));
        ref.invalidate(bundleProvider);
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.mgrMasters)),
      floatingActionButton: FloatingActionButton(key: const Key('master-add'), tooltip: l.add, onPressed: open, child: const Icon(Icons.add_rounded)),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(children: [
            for (final e in masterSpecs.keys)
              Padding(padding: const EdgeInsets.only(right: AppSpacing.sm), child: ChoiceChip(key: Key('entity-$e'), label: Text(e), selected: _entity == e, onSelected: (_) => setState(() => _entity = e))),
          ]),
        ),
        Expanded(
          child: AsyncView<List<Map<String, dynamic>>>(
            value: rows,
            onRetry: () => ref.invalidate(masterListProvider(_entity)),
            isEmpty: (v) => v.isEmpty,
            empty: EmptyState(title: l.noData),
            data: (v) => ListView(children: [
              for (final r in v)
                ListTile(
                  key: Key('master-${rowTitle(_entity, r)}'),
                  title: Text(rowTitle(_entity, r)),
                  subtitle: Text([r['name'], r['type'], r['status'], if (r['active'] == false) l.inactive].whereType<Object>().join(' · ')),
                  trailing: const Icon(Icons.edit_rounded),
                  onTap: () => open(r),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class MasterFormScreen extends ConsumerStatefulWidget {
  const MasterFormScreen({super.key, required this.entity, this.row});
  final String entity;
  final Map<String, dynamic>? row;

  @override
  ConsumerState<MasterFormScreen> createState() => _MasterFormScreenState();
}

class _MasterFormScreenState extends ConsumerState<MasterFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, Object?> _values = {
    for (final f in masterSpecs[widget.entity]!) f.key: f.kind == FieldKind.secret ? '' : (widget.row?[f.key] ?? (f.kind == FieldKind.boolean ? (f.key == 'active') : null)),
  };
  late final Map<String, TextEditingController> _text = {
    for (final f in masterSpecs[widget.entity]!)
      if (f.kind == FieldKind.text || f.kind == FieldKind.number || f.kind == FieldKind.secret) f.key: TextEditingController(text: _values[f.key] == null ? '' : '${_values[f.key]}'),
  };
  bool _busy = false;

  bool get _create => widget.row == null;

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    for (final e in _text.entries) {
      _values[e.key] = e.value.text;
    }
    final body = masterBody(masterSpecs[widget.entity]!, _values, create: _create);
    setState(() => _busy = true);
    final ok = await runAndReport(context, () => ref.read(managerRepositoryProvider).saveMaster(widget.entity, widget.row?['id'] as String?, body), success: context.l10n.saved);
    if (mounted) setState(() => _busy = false);
    if (ok && mounted) Navigator.pop(context, true);
  }

  Widget _field(FieldSpec f, List<Map<String, dynamic>> sites, List<Map<String, dynamic>> vehicles, List<Map<String, dynamic>> units) {
    final l = context.l10n;
    final locked = !_create && f.createOnly;
    String? need(String? v) => f.required && (v ?? '').trim().isEmpty ? l.fieldRequired : null;
    Widget pick(List<(String, String)> items) => DropdownButtonFormField<String>(
          key: Key('mf-${f.key}'),
          isExpanded: true,
          initialValue: items.any((i) => i.$1 == _values[f.key]) ? '${_values[f.key]}' : null,
          decoration: InputDecoration(labelText: f.key),
          items: [for (final (v, label) in items) DropdownMenuItem(value: v, child: Text(label, overflow: TextOverflow.ellipsis))],
          onChanged: locked ? null : (v) => setState(() => _values[f.key] = v),
          validator: (v) => need(v),
        );
    return switch (f.kind) {
      FieldKind.boolean => SwitchListTile(key: Key('mf-${f.key}'), contentPadding: EdgeInsets.zero, title: Text(f.key), value: _values[f.key] == true, onChanged: (v) => setState(() => _values[f.key] = v)),
      FieldKind.choice => pick([for (final o in f.options) (o, o)]),
      FieldKind.site => pick([for (final s in sites) ('${s['id']}', '${s['code']} · ${s['name']}')]),
      FieldKind.vehicle => pick([for (final v in vehicles) ('${v['id']}', '${v['regNo']}')]),
      FieldKind.storageUnit => pick([for (final u in units) ('${u['id']}', '${u['code']}')]),
      FieldKind.number => TextFormField(
          key: Key('mf-${f.key}'),
          controller: _text[f.key],
          enabled: !locked,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: InputDecoration(labelText: f.key),
          validator: (v) => need(v) ?? ((v ?? '').trim().isEmpty || double.tryParse(v!.trim().replaceAll(',', '.')) != null ? null : l.notANumber),
        ),
      FieldKind.secret => TextFormField(
          key: Key('mf-${f.key}'),
          controller: _text[f.key],
          obscureText: true,
          decoration: InputDecoration(labelText: f.key, helperText: _create ? l.secretHelp : l.secretKeep),
          validator: (v) => _create && ((v ?? '').length < 16 || v!.length > 128) ? l.secretLength : (!_create && (v ?? '').isNotEmpty && (v!.length < 16 || v.length > 128) ? l.secretLength : null),
        ),
      FieldKind.text => TextFormField(key: Key('mf-${f.key}'), controller: _text[f.key], enabled: !locked, decoration: InputDecoration(labelText: f.key, helperText: locked ? l.immutable : null), validator: locked ? null : need),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final sites = ref.watch(sitesProvider);
    final vehicles = widget.entity == 'devices' ? (ref.watch(masterListProvider('vehicles')).value ?? const []) : const <Map<String, dynamic>>[];
    final units = widget.entity == 'devices' ? (ref.watch(masterListProvider('storage-units')).value ?? const []) : const <Map<String, dynamic>>[];
    return Scaffold(
      appBar: AppBar(title: Text('${widget.entity} · ${_create ? l.add : rowTitle(widget.entity, widget.row!)}')),
      body: Form(
        key: _form,
        child: ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
          for (final f in masterSpecs[widget.entity]!) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.md), child: _field(f, sites, vehicles, units)),
          AppButton(key: const Key('mf-save'), label: l.save, icon: Icons.save_rounded, busy: _busy, onPressed: _busy ? null : _save),
        ]),
      ),
    );
  }
}

// ───────────── Users (ADMIN, Section 10.6 #8) ─────────────

final usersProvider = FutureProvider.autoDispose.family<ApiPage, String?>((ref, role) => ref.watch(managerRepositoryProvider).users(role: role));

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  String? _role;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Future<void> open([Map<String, dynamic>? u]) async {
      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => UserFormScreen(user: u)));
      if (saved == true) ref.invalidate(usersProvider(_role));
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.mgrUsers)),
      floatingActionButton: FloatingActionButton(key: const Key('user-add'), tooltip: l.add, onPressed: open, child: const Icon(Icons.person_add_rounded)),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(children: [
            for (final r in const [null, 'ADMIN', 'MANAGER', 'OPERATOR', 'DRIVER'])
              Padding(padding: const EdgeInsets.only(right: AppSpacing.sm), child: ChoiceChip(label: Text(r ?? l.all), selected: _role == r, onSelected: (_) => setState(() => _role = r))),
          ]),
        ),
        Expanded(
          child: AsyncView<ApiPage>(
            value: ref.watch(usersProvider(_role)),
            onRetry: () => ref.invalidate(usersProvider(_role)),
            isEmpty: (p) => p.items.isEmpty,
            empty: EmptyState(title: l.noData),
            data: (p) => ListView(children: [
              for (final u in p.items)
                ListTile(
                  key: Key('user-${u['name']}'),
                  title: Text('${u['name']}'),
                  subtitle: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('${u['role']} · ${u['status']} · ${u['phone'] ?? u['email'] ?? ''}'),
                    if (u['status'] == 'DISABLED') StatusChip(level: StatusLevel.critical, label: l.disabled),
                  ]),
                  onTap: () => open(u),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class UserFormScreen extends ConsumerStatefulWidget {
  const UserFormScreen({super.key, this.user});
  final Map<String, dynamic>? user;

  @override
  ConsumerState<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends ConsumerState<UserFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user?['name'] as String?);
  late final _phone = TextEditingController(text: widget.user?['phone'] as String? ?? '+91');
  late final _email = TextEditingController(text: widget.user?['email'] as String?);
  late final _emergency = TextEditingController(text: widget.user?['emergencyContactPhone'] as String?);
  late String _role = widget.user?['role'] as String? ?? 'DRIVER';
  late String? _site = widget.user?['siteId'] as String?;
  late String _language = widget.user?['language'] as String? ?? 'mr';
  bool _busy = false;

  bool get _create => widget.user == null;
  bool get _field => _role == 'DRIVER' || _role == 'OPERATOR';
  static final _e164 = RegExp(r'^\+[1-9]\d{7,14}$');

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _emergency]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    if (!_form.currentState!.validate()) return;
    final body = {
      'name': _name.text.trim(),
      'role': _role,
      'language': _language,
      'siteId': ?_site,
      if (_emergency.text.trim().isNotEmpty) 'emergencyContactPhone': _emergency.text.trim(),
      // identity fields only on create (they change through Supabase afterwards)
      if (_create && _field) 'phone': _phone.text.trim(),
      if (_create && !_field) 'email': _email.text.trim(),
    };
    setState(() => _busy = true);
    final ok = await runAndReport(context, () => ref.read(managerRepositoryProvider).saveUser(widget.user?['id'] as String?, body), success: l.saved);
    if (mounted) setState(() => _busy = false);
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final sites = ref.watch(sitesProvider);
    final disabled = widget.user?['status'] == 'DISABLED';
    return Scaffold(
      appBar: AppBar(title: Text(_create ? l.addUser : '${widget.user!['name']}')),
      body: Form(
        key: _form,
        child: ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
          TextFormField(key: const Key('uf-name'), controller: _name, decoration: InputDecoration(labelText: l.name), validator: (v) => (v ?? '').trim().length < 2 ? l.fieldRequired : null),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: const Key('uf-role'),
            initialValue: _role,
            decoration: InputDecoration(labelText: l.roleLabel),
            items: [for (final r in const ['DRIVER', 'OPERATOR', 'MANAGER', 'ADMIN']) DropdownMenuItem(value: r, child: Text(r))],
            onChanged: (v) => setState(() => _role = v ?? _role),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_field)
            TextFormField(key: const Key('uf-phone'), controller: _phone, enabled: _create, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: l.phoneE164, helperText: _create ? null : l.immutable), validator: (v) => !_create || _e164.hasMatch((v ?? '').trim()) ? null : l.phoneInvalidE164)
          else
            TextFormField(key: const Key('uf-email'), controller: _email, enabled: _create, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: l.emailLabel, helperText: _create ? null : l.immutable), validator: (v) => !_create || (v ?? '').contains('@') ? null : l.emailInvalid),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            key: const Key('uf-site'),
            isExpanded: true,
            initialValue: sites.any((s) => s['id'] == _site) ? _site : null,
            decoration: InputDecoration(labelText: l.siteLabel),
            items: [for (final s in sites) DropdownMenuItem(value: '${s['id']}', child: Text('${s['code']} · ${s['name']}', overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _site = v),
            validator: (v) => _field && v == null ? l.siteRequired : null,
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _language,
            decoration: InputDecoration(labelText: l.language),
            items: const [DropdownMenuItem(value: 'en', child: Text('English')), DropdownMenuItem(value: 'hi', child: Text('हिन्दी')), DropdownMenuItem(value: 'mr', child: Text('मराठी'))],
            onChanged: (v) => setState(() => _language = v ?? _language),
          ),
          if (_role == 'DRIVER') ...[
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _emergency, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: l.emergencyContact), validator: (v) => (v ?? '').trim().isEmpty || _e164.hasMatch(v!.trim()) ? null : l.phoneInvalidE164),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppButton(key: const Key('uf-save'), label: l.save, icon: Icons.save_rounded, busy: _busy, onPressed: _busy ? null : _save),
          if (!_create) ...[
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const Key('uf-disable'),
              label: disabled ? l.enableUser : l.disableUser,
              kind: disabled ? AppButtonKind.outlined : AppButtonKind.danger,
              onPressed: () async {
                if (!disabled && !await confirm(context, l.disableUserConfirm, danger: true)) return;
                if (context.mounted && await runAndReport(context, () => ref.read(managerRepositoryProvider).setUserDisabled('${widget.user!['id']}', !disabled), success: l.saved) && context.mounted) Navigator.pop(context, true);
              },
            ),
          ],
        ]),
      ),
    );
  }
}

// ───────────── Remote config (ADMIN, Section 10.6 #9) ─────────────

/// The keys and value shapes the server accepts (server/src/modules/remote-config/config-keys.ts).
final configValueProvider = FutureProvider.autoDispose.family<Object?, String>((ref, k) => ref.watch(managerRepositoryProvider).config(k));

const configKeys = ['persistMinutes', 'ackMinutes', 'offerMinutes', 'editWindowMin', 'safetyMarginH', 'driftSlopeMax', 'rescueRadiusKm', 'gpsIntervalSec', 'emissionFactorKgPerKm', 'featureFlags'];

class ConfigScreen extends ConsumerWidget {
  const ConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.read(managerRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.mgrConfig)),
      body: ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
        Text(l.configHint, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppSpacing.md),
        for (final k in configKeys)
          Consumer(
            builder: (context, ref, _) {
              final s = ref.watch(configValueProvider(k));
              return ListTile(
              key: Key('cfg-$k'),
              contentPadding: EdgeInsets.zero,
              title: Text(k),
              subtitle: Text(s.hasError ? l.notSet : (s.hasValue ? jsonEncode(s.value) : '…'), maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.edit_rounded),
              onTap: () async {
                final r = await showDialog<Map<String, String>>(
                  context: context,
                  builder: (d) => TextFieldsDialog(
                    title: k,
                    saveLabel: l.save,
                    fields: [DialogField('cfg-value', l.jsonValue, initial: s.hasValue ? const JsonEncoder.withIndent('  ').convert(s.value) : '', maxLines: 8)],
                  ),
                );
                final v = r?['cfg-value'];
                if (v == null || !context.mounted) return;
                Object? parsed;
                try {
                  parsed = jsonDecode(v);
                } on FormatException {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.invalidJson)));
                  return;
                }
                // the server validates the shape (400 INVALID_CONFIG_VALUE) and the message is shown
                if (await runAndReport(context, () => repo.setConfig(k, parsed), success: l.saved)) ref.invalidate(configValueProvider(k));
              },
              );
            },
          ),
      ]),
    );
  }
}
