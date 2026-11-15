import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/l10n.dart';
import '../theme/app_spacing.dart';
import 'tag_reader.dart';

/// QR fallback (FO-FR-05) with the camera. Also reads I-CCMS labels (trace URL → batch code).
class QrTagReader implements TagReader {
  const QrTagReader();

  @override
  TagKind get kind => TagKind.qr;

  @override
  Future<TagRead?> read(BuildContext context) => Navigator.of(context).push<TagRead>(MaterialPageRoute(builder: (_) => const QrScanScreen()));
}

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode, BarcodeFormat.code128, BarcodeFormat.dataMatrix]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.scanQr)),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            if (_done) return;
            for (final b in capture.barcodes) {
              final v = b.rawValue == null ? null : normaliseTagValue(TagKind.qr, b.rawValue!);
              if (v != null) {
                _done = true;
                Navigator.pop(context, TagRead(TagKind.qr, v));
                return;
              }
            }
          },
        ),
        // Aiming frame
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(AppRadius.card)),
          ),
        ),
        Positioned(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: AppSpacing.xxl,
          child: Text(l.scanQrHelp, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, shadows: [Shadow(blurRadius: 4)])),
        ),
      ]),
    );
  }
}
