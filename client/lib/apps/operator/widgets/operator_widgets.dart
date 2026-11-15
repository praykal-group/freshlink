import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/printing/label_printer.dart';
import '../../../core/providers.dart';
import '../../../core/tags/tag_reader.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/qr_view.dart';
import '../../../shared/widgets/status.dart';
import '../providers.dart';

String batchStatusText(AppLocalizations l, String s) => switch (s) {
      'REGISTERED' => l.stRegistered,
      'GRADED' => l.stGraded,
      'STORED' => l.stStored,
      'ALLOCATED' => l.stAllocated,
      'LOADED' => l.stLoaded,
      'IN_TRANSIT' => l.stInTransit,
      'DIVERTED' => l.stDiverted,
      'DELIVERED' => l.stDelivered,
      'PARTIALLY_DELIVERED' => l.stPartial,
      'REJECTED' => l.stRejected,
      'SPOILED' => l.stSpoiled,
      _ => s,
    };

StatusLevel batchStatusLevel(String s) => switch (s) {
      'REJECTED' || 'SPOILED' => StatusLevel.critical,
      'DIVERTED' || 'PARTIALLY_DELIVERED' => StatusLevel.watch,
      'DELIVERED' || 'STORED' || 'GRADED' => StatusLevel.safe,
      _ => StatusLevel.info,
    };

String storagePathText(AppLocalizations l, String path) => switch (path) {
      'BLAST_CHILLER' => l.pathBlastChiller,
      'RIPENING_CHAMBER' => l.pathRipening,
      'COLD_ROOM' => l.pathColdRoom,
      _ => path,
    };

/// FO-FR-05: one big button per reader (gloves: 56 dp+). Returns the tag read, or null.
class TagPicker extends ConsumerWidget {
  const TagPicker({super.key, required this.onRead, this.current});
  final ValueChanged<TagRead> onRead;
  final TagRead? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final readers = ref.watch(tagReadersProvider);
    Future<void> use(TagKind k) async {
      final r = await readers[k]?.read(context);
      if (r != null) {
        HapticFeedback.mediumImpact();
        onRead(r);
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppButton(key: const Key('tag-nfc'), label: l.tagNfc, icon: Icons.nfc_rounded, kind: AppButtonKind.tonal, onPressed: () => use(TagKind.nfc)),
      const SizedBox(height: AppSpacing.md),
      AppButton(key: const Key('tag-qr'), label: l.tagQr, icon: Icons.qr_code_scanner_rounded, kind: AppButtonKind.tonal, onPressed: () => use(TagKind.qr)),
      const SizedBox(height: AppSpacing.md),
      AppButton(key: const Key('tag-uhf'), label: l.tagWedge, icon: Icons.sensors_rounded, kind: AppButtonKind.outlined, onPressed: () => use(TagKind.uhf)),
      if (current != null) ...[
        const SizedBox(height: AppSpacing.lg),
        AppCard(status: StatusLevel.safe, child: Row(children: [
          Icon(Icons.check_circle_rounded, color: context.palette.safe),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text('${current!.kind.api} · ${l.tagRead(current!.uid)}', key: const Key('tag-current'))),
        ])),
      ],
    ]);
  }
}

/// Numeric field with a range check and the mic button (FO-NFR voice input on numeric fields).
class NumberField extends ConsumerWidget {
  const NumberField({super.key, required this.label, required this.controller, this.unit, this.min, this.max, this.required = false, this.fieldKey, this.decimals = true});
  final String label;
  final TextEditingController controller;
  final String? unit;
  final num? min;
  final num? max;
  final bool required;
  final Key? fieldKey;
  final bool decimals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return AppTextField(
      fieldKey: fieldKey,
      label: label,
      controller: controller,
      unit: unit,
      keyboardType: TextInputType.numberWithOptions(decimal: decimals, signed: (min ?? 0) < 0),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]'))],
      helper: min != null && max != null ? '$min – $max${unit == null ? '' : ' $unit'}' : null,
      validator: (v) => Validators.numberInRange(v, min: min, max: max, required: required),
      onVoice: () async {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(SnackBar(content: Text(l.listening), duration: const Duration(seconds: 6)));
        final n = await ref.read(voiceInputProvider).listen(ref.read(localeProvider).languageCode);
        messenger.hideCurrentSnackBar();
        if (n == null) {
          messenger.showSnackBar(SnackBar(content: Text(l.voiceNotHeard)));
        } else {
          controller.text = n.toString();
        }
      },
    );
  }
}

/// The label as shown on screen and shared as an image (FO-FR-09 fallback).
class LabelCard extends StatelessWidget {
  const LabelCard({super.key, required this.data});
  final LabelData data;

  @override
  Widget build(BuildContext context) {
    // Always black on white like the paper label, whatever the theme.
    const ink = TextStyle(color: Colors.black);
    final d = data.caughtOrHarvestedAt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return Container(
      width: 320,
      color: Colors.white,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('I-CCMS', style: ink.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: AppSpacing.xs),
        Text(data.productName, style: ink.copyWith(fontSize: 22, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
        Text(data.code, key: const Key('label-code'), style: ink.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
        const Divider(color: Colors.black),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${data.weightKg.toStringAsFixed(1)} kg', style: ink.copyWith(fontSize: 16)),
          Text(data.grade == null ? 'Grade –' : 'Grade ${data.grade}', style: ink.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: AppSpacing.xs),
        Text('${data.sourceSite} · ${two(d.day)}-${two(d.month)}-${d.year} ${two(d.hour)}:${two(d.minute)}', style: ink.copyWith(fontSize: 13), textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.md),
        QrView(data: data.qrData, size: 180),
      ]),
    );
  }
}

/// Renders [boundaryKey]'s widget to PNG and opens the share sheet.
Future<void> shareWidgetAsImage(GlobalKey boundaryKey, String name) async {
  final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 3);
  final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name.png');
  await file.writeAsBytes(png);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')], title: name));
}

/// Label preview with Print (configured Bluetooth printer) and Share image.
class LabelActions extends ConsumerStatefulWidget {
  const LabelActions({super.key, required this.data});
  final LabelData data;

  @override
  ConsumerState<LabelActions> createState() => _LabelActionsState();
}

class _LabelActionsState extends ConsumerState<LabelActions> {
  final _boundary = GlobalKey();
  bool _printing = false;

  Future<void> _print() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final mac = ref.read(printerProvider).value;
    if (mac == null) {
      messenger.showSnackBar(SnackBar(content: Text(l.noPrinter)));
      return;
    }
    setState(() => _printing = true);
    try {
      final ok = await ref.read(labelPrinterProvider).print(mac, await labelBytes(widget.data));
      messenger.showSnackBar(SnackBar(content: Text(ok ? l.printed : l.printFailed)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.printFailed)));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: FittedBox(child: RepaintBoundary(key: _boundary, child: LabelCard(data: widget.data)))),
      const SizedBox(height: AppSpacing.lg),
      AppButton(key: const Key('print'), label: l.print, icon: Icons.print_rounded, busy: _printing, onPressed: _print),
      const SizedBox(height: AppSpacing.md),
      AppButton(key: const Key('share-label'), label: l.shareImage, icon: Icons.share_rounded, kind: AppButtonKind.outlined, onPressed: () => shareWidgetAsImage(_boundary, widget.data.code)),
    ]);
  }
}
