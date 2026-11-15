import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/media/voice_recorder.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/screens/camera_screen.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/status.dart';
import '../data/driver_repository.dart';
import '../providers.dart';
import '../widgets/driver_widgets.dart';

final voiceRecorderProvider = Provider<VoiceRecorder>((_) => RecordVoiceRecorder());

const kMaxVoice = Duration(seconds: 60);

(String, IconData) incidentLabel(AppLocalizations l, IncidentKind k) => switch (k) {
      IncidentKind.delay => (l.incDelay, Icons.schedule_rounded),
      IncidentKind.breakdown => (l.incBreakdown, Icons.car_repair_rounded),
      IncidentKind.accident => (l.incAccident, Icons.car_crash_rounded),
      IncidentKind.roadblock => (l.incRoadblock, Icons.block_rounded),
      IncidentKind.reeferFault => (l.incReeferFault, Icons.ac_unit_rounded),
    };

/// Section 10.5 #7 / DA-FR-09: tap a kind, then Send (2 taps); photo and voice (≤ 60 s) are
/// optional. Queued offline; the server replans when it arrives.
class IncidentScreen extends ConsumerStatefulWidget {
  const IncidentScreen({super.key});

  @override
  ConsumerState<IncidentScreen> createState() => _IncidentScreenState();
}

class _IncidentScreenState extends ConsumerState<IncidentScreen> {
  IncidentKind? _kind;
  CapturedPhoto? _photo;
  VoiceNote? _voice;
  bool _recording = false;
  bool _micDenied = false;
  Timer? _limit;
  int _elapsed = 0;
  Timer? _tick;
  bool _sending = false;

  @override
  void dispose() {
    _limit?.cancel();
    _tick?.cancel();
    if (_recording) unawaited(ref.read(voiceRecorderProvider).cancel());
    super.dispose();
  }

  Future<void> _toggleVoice() async {
    final rec = ref.read(voiceRecorderProvider);
    if (_recording) return _stopVoice();
    if (!await rec.start()) {
      setState(() => _micDenied = true);
      return;
    }
    setState(() {
      _recording = true;
      _micDenied = false;
      _elapsed = 0;
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _elapsed++));
    _limit = Timer(kMaxVoice, _stopVoice); // DA-FR-09 max 60 s
  }

  Future<void> _stopVoice() async {
    _limit?.cancel();
    _tick?.cancel();
    final note = await ref.read(voiceRecorderProvider).stop();
    if (mounted) {
      setState(() {
        _recording = false;
        _voice = note;
      });
    }
  }

  Future<void> _takePhoto() async {
    final l = context.l10n;
    final p = await ref.read(photoCaptureProvider)(context, title: l.incPhoto, instruction: l.incPhotoHint, fileStem: 'incident-${DateTime.now().millisecondsSinceEpoch}');
    if (p == null) return;
    unawaited(discardOriginal(p));
    if (mounted) setState(() => _photo = p);
  }

  Future<void> _send() async {
    final trip = ref.read(currentTripProvider).value;
    if (trip == null || _kind == null) return;
    if (_recording) await _stopVoice();
    setState(() => _sending = true);
    await ref.read(driverRepositoryProvider).reportIncident(
          trip.id,
          _kind!,
          at: ref.read(lastFixProvider),
          photo: _photo == null ? null : (path: _photo!.path, bytes: _photo!.sizeBytes),
          voice: _voice == null ? null : (path: _voice!.path, bytes: _voice!.bytes, seconds: _voice!.seconds),
        );
    unawaited(ref.read(syncSchedulerProvider)?.syncNow());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.incSent)));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(l.reportIncident)),
      body: SpeedLockGate(
        child: ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
          // Tiles size to their text (a fixed grid aspect clipped Hindi / Marathi labels at text
          // scale 2.0, M12 test): two columns, one when the text is very large.
          LayoutBuilder(builder: (context, box) {
            final cols = MediaQuery.textScalerOf(context).scale(1) > 1.5 ? 1 : 2;
            final w = (box.maxWidth - AppSpacing.md * (cols - 1)) / cols;
            return Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: [
              for (final k in IncidentKind.values)
                Builder(builder: (context) {
                  final (label, icon) = incidentLabel(l, k);
                  final selected = _kind == k;
                  return SizedBox(
                    width: w,
                    child: Semantics(
                      selected: selected,
                      button: true,
                      child: Material(
                        color: selected ? p.primary : p.surfaceVariant,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          key: Key('inc-${k.name}'),
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => setState(() => _kind = k),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 96), // big targets (DA-NFR)
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(icon, size: 36, color: selected ? p.onPrimary : p.textPrimary),
                                const SizedBox(height: AppSpacing.xs),
                                Text(label, textAlign: TextAlign.center, style: TextStyle(color: selected ? p.onPrimary : p.textPrimary, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ]);
          }),
          const SizedBox(height: AppSpacing.lg),
          Row(children: [
            Expanded(
              child: AppButton(
                key: const Key('inc-photo'),
                label: _photo == null ? l.incPhoto : l.incPhotoDone,
                icon: _photo == null ? Icons.photo_camera_rounded : Icons.check_rounded,
                kind: AppButtonKind.outlined,
                onPressed: _takePhoto,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppButton(
                key: const Key('inc-voice'),
                label: _recording ? l.incVoiceStop(kMaxVoice.inSeconds - _elapsed) : (_voice == null ? l.incVoice : l.incVoiceDone(_voice!.seconds)),
                icon: _recording ? Icons.stop_rounded : Icons.mic_rounded,
                kind: _recording ? AppButtonKind.danger : AppButtonKind.outlined,
                onPressed: _toggleVoice,
              ),
            ),
          ]),
          if (_micDenied) ...[const SizedBox(height: AppSpacing.sm), AppCard(status: StatusLevel.watch, child: Text(l.micDenied))],
          if (_photo != null) ...[
            const SizedBox(height: AppSpacing.md),
            ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(_photo!.path), height: 120, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppButton(key: const Key('inc-send'), label: l.incSend, icon: Icons.send_rounded, busy: _sending, onPressed: _kind == null || _sending ? null : _send),
          const SizedBox(height: AppSpacing.sm),
          Text(l.incQueuedHint, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}
