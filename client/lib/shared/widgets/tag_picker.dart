import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/tags/nfc_tag_reader.dart';
import '../../core/tags/qr_tag_reader.dart';
import '../../core/tags/tag_reader.dart';
import '../../core/tags/wedge_tag_reader.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import 'app_button.dart';
import 'status.dart';

/// Readers in the order offered (FO-FR-05, DA-FR-11). Overridden in tests. Shared by the operator
/// (tagging, receiving, loading) and the driver (crate scan at delivery).
final tagReadersProvider = Provider<Map<TagKind, TagReader>>((_) => const {
      TagKind.nfc: NfcTagReader(),
      TagKind.qr: QrTagReader(),
      TagKind.uhf: WedgeTagReader(),
    });

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
