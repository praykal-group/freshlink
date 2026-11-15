import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/status.dart';
import '../data/driver_repository.dart';
import '../providers.dart';
import '../widgets/driver_widgets.dart';

String preCheckProblemText(AppLocalizations l, String code) => switch (code) {
      'REEFER_OFF' => l.pcReeferOff,
      'DOORS_OPEN' => l.pcDoorsOpen,
      'SETPOINT_OUT_OF_RANGE' => l.pcSetpointOut,
      'INCOMPATIBLE_CARGO' => l.pcIncompatible,
      _ => code,
    };

/// Section 10.5 #2 / DA-FR-03: reefer ON, setpoint correct, doors closed — saved with a timestamp
/// by the server (also when it fails, so the manager sees every attempt).
class PreCheckScreen extends ConsumerStatefulWidget {
  const PreCheckScreen({super.key});

  @override
  ConsumerState<PreCheckScreen> createState() => _PreCheckScreenState();
}

class _PreCheckScreenState extends ConsumerState<PreCheckScreen> {
  bool _reeferOn = false;
  bool _setpointChecked = false;
  bool _doorsClosed = false;
  final _setpoint = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  PreCheckFailed? _failed;
  String? _error;

  @override
  void dispose() {
    _setpoint.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final trip = ref.read(currentTripProvider).value;
    if (trip == null) return;
    setState(() {
      _busy = true;
      _failed = null;
      _error = null;
    });
    try {
      await ref.read(driverRepositoryProvider).preCheck(trip.id, reeferOn: _reeferOn, setpointC: parseNumber(_setpoint.text)!, doorsClosed: _doorsClosed);
      await ref.read(currentTripProvider.notifier).refresh();
      if (mounted) context.pop();
    } on PreCheckFailed catch (f) {
      setState(() => _failed = f);
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final all = _reeferOn && _setpointChecked && _doorsClosed;
    return Scaffold(
      appBar: AppBar(title: Text(l.preCheck)),
      body: Form(
        key: _form,
        child: ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
          SwitchListTile(key: const Key('pc-reefer'), value: _reeferOn, onChanged: (v) => setState(() => _reeferOn = v), title: Text(l.pcReeferOn), secondary: const Icon(Icons.ac_unit_rounded)),
          SwitchListTile(key: const Key('pc-setpoint-ok'), value: _setpointChecked, onChanged: (v) => setState(() => _setpointChecked = v), title: Text(l.pcSetpointChecked), secondary: const Icon(Icons.thermostat_rounded)),
          SwitchListTile(key: const Key('pc-doors'), value: _doorsClosed, onChanged: (v) => setState(() => _doorsClosed = v), title: Text(l.pcDoorsClosed), secondary: const Icon(Icons.door_front_door_rounded)),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            fieldKey: const Key('pc-setpoint'),
            label: l.pcSetpoint,
            unit: '°C',
            controller: _setpoint,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            validator: (v) => Validators.numberInRange(v, min: -30, max: 30),
          ),
          if (_failed != null) ...[
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              key: const Key('pc-failed'),
              status: StatusLevel.critical,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.pcFailed, style: Theme.of(context).textTheme.titleSmall),
                for (final p in _failed!.problems) Text('• ${preCheckProblemText(l, p)}'),
                if (_failed!.allowedMin != null && _failed!.allowedMax != null)
                  Text(l.pcAllowedRange(_failed!.allowedMin!.toStringAsFixed(1), _failed!.allowedMax!.toStringAsFixed(1))),
              ]),
            ),
          ],
          if (_error != null) ...[const SizedBox(height: AppSpacing.lg), AppCard(status: StatusLevel.critical, child: Text(_error!))],
          const SizedBox(height: AppSpacing.xl),
          AppButton(key: const Key('pc-submit'), label: l.pcSubmit, icon: Icons.check_rounded, busy: _busy, onPressed: all && !_busy ? _submit : null),
          if (!all) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Text(l.pcAllNeeded, style: Theme.of(context).textTheme.bodySmall)),
        ]),
      ),
    );
  }
}
