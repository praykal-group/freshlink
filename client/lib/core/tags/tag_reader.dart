import 'package:flutter/widgets.dart';

/// Server TagType (Prisma enum).
enum TagKind { nfc, qr, uhf }

extension TagKindApi on TagKind {
  String get api => switch (this) {
        TagKind.nfc => 'NFC',
        TagKind.qr => 'QR',
        TagKind.uhf => 'UHF',
      };
}

class TagRead {
  const TagRead(this.kind, this.uid);
  final TagKind kind;
  final String uid;

  @override
  bool operator ==(Object other) => other is TagRead && other.kind == kind && other.uid == uid;

  @override
  int get hashCode => Object.hash(kind, uid);

  @override
  String toString() => 'TagRead(${kind.api}, $uid)';
}

/// FO-FR-05: NFC tap, QR fallback, UHF RFID through a Bluetooth handheld that types like a keyboard
/// (Section 10.4 `TagReader` → NfcTagReader, QrTagReader, WedgeTagReader).
abstract class TagReader {
  TagKind get kind;

  /// Reads one tag, or null when the user cancelled.
  Future<TagRead?> read(BuildContext context);
}

/// Server rule for tag UIDs: `^[A-Za-z0-9:_-]{4,128}$` (AttachTagDto).
final _uidPattern = RegExp(r'^[A-Za-z0-9:_-]{4,128}$');

/// NFC UID bytes → upper-case hex without separators (`04A1B2C3D4E5F6`).
String nfcUid(List<int> bytes) => bytes.map((b) => (b & 0xff).toRadixString(16).padLeft(2, '0')).join().toUpperCase();

/// Normalises what a scanner returned. QR codes on I-CCMS labels hold the trace URL
/// (`…/t/<code>?s=…`): the batch code is the identifier then. Returns null when unusable.
String? normaliseTagValue(TagKind kind, String raw) {
  var v = raw.trim();
  if (kind == TagKind.qr) {
    final uri = Uri.tryParse(v);
    if (uri != null && uri.hasScheme && uri.pathSegments.length >= 2 && uri.pathSegments[uri.pathSegments.length - 2] == 't') {
      v = uri.pathSegments.last;
    }
  }
  if (kind == TagKind.uhf || kind == TagKind.nfc) v = v.replaceAll(RegExp(r'[\s]'), '').toUpperCase();
  return _uidPattern.hasMatch(v) ? v : null;
}
