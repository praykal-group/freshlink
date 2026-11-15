import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// QR code drawn from the `qr` package (no image library): black modules on white with a quiet
/// zone, so labels and shared images scan reliably (D-130).
class QrView extends StatelessWidget {
  const QrView({super.key, required this.data, this.size = 160});
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final code = QrCode(payload: QrPayload.fromString(data), errorCorrectLevel: QrErrorCorrectLevel.medium);
    final image = QrImage(code);
    return Semantics(
      label: 'QR',
      image: true,
      child: CustomPaint(size: Size.square(size), painter: _QrPainter(image)),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);
  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    const quiet = 4; // modules of white border
    final n = image.moduleCount + quiet * 2;
    final cell = size.width / n;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final dark = Paint()..color = Colors.black;
    for (var y = 0; y < image.moduleCount; y++) {
      for (var x = 0; x < image.moduleCount; x++) {
        if (image.isDark(y, x)) canvas.drawRect(Rect.fromLTWH((x + quiet) * cell, (y + quiet) * cell, cell + 0.5, cell + 0.5), dark);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}
