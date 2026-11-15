import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

import '../l10n/l10n.dart';
import '../theme/app_spacing.dart';
import 'tag_reader.dart';

/// NFC 13.56 MHz tag tap (FO-FR-05): the tag's UID as upper-case hex. Shows a "hold the tag to the
/// back of the phone" sheet while the session runs; closing it cancels.
class NfcTagReader implements TagReader {
  const NfcTagReader();

  @override
  TagKind get kind => TagKind.nfc;

  static Future<bool> available() async {
    try {
      return await NfcManager.instance.checkAvailability() == NfcAvailability.enabled;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<TagRead?> read(BuildContext context) async {
    final l = context.l10n;
    if (!await available()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.nfcUnavailable)));
      }
      return null;
    }
    final found = Completer<TagRead?>();
    await NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
      onDiscovered: (tag) async {
        final android = NfcTagAndroid.from(tag);
        final uid = android == null ? null : normaliseTagValue(TagKind.nfc, nfcUid(android.id));
        if (!found.isCompleted) found.complete(uid == null ? null : TagRead(TagKind.nfc, uid));
        await NfcManager.instance.stopSession();
      },
    );
    if (!context.mounted) return null;
    final sheet = showModalBottomSheet<void>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.nfc_rounded, size: 64),
          const SizedBox(height: AppSpacing.lg),
          Text(l.nfcHold, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        ]),
      ),
    );
    unawaited(sheet.then((_) {
      if (!found.isCompleted) {
        found.complete(null);
        NfcManager.instance.stopSession().catchError((_) {});
      }
    }));
    final result = await found.future;
    if (result != null && context.mounted) Navigator.of(context).maybePop();
    return result;
  }
}
