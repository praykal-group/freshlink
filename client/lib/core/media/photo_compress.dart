import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// FO-NFR-04: photos are sent at 1280 px on the long side and under 500 KB; the full-resolution
/// original stays on the phone until the batch is graded.
const kLongSide = 1280;
const kMaxBytes = 500 * 1024;
const kQualities = [85, 75, 65, 55, 45];

/// Target size keeping the aspect ratio; never upscales.
(int, int) targetSize(int width, int height, {int longSide = kLongSide}) {
  final long = width > height ? width : height;
  if (long <= longSide) return (width, height);
  final scale = longSide / long;
  return ((width * scale).round(), (height * scale).round());
}

/// JPEG encoder (platform plugin in the app; a fake in tests).
typedef JpegEncoder = Future<Uint8List> Function(Uint8List source, {required int width, required int height, required int quality});

Future<Uint8List> _pluginEncoder(Uint8List source, {required int width, required int height, required int quality}) =>
    FlutterImageCompress.compressWithList(source, minWidth: width, minHeight: height, quality: quality, format: CompressFormat.jpeg, keepExif: false);

class CompressedPhoto {
  const CompressedPhoto(this.bytes, this.width, this.height, this.quality);
  final Uint8List bytes;
  final int width;
  final int height;
  final int quality;
}

/// Lowers the JPEG quality step by step until the photo is under [maxBytes]. If even the lowest
/// quality is too big, it shrinks the long side by 20 % and tries again (rare: very noisy images).
Future<CompressedPhoto> compressPhoto(Uint8List source, int width, int height, {JpegEncoder encode = _pluginEncoder, int maxBytes = kMaxBytes}) async {
  var long = kLongSide;
  while (true) {
    final (w, h) = targetSize(width, height, longSide: long);
    Uint8List? last;
    for (final q in kQualities) {
      last = await encode(source, width: w, height: h, quality: q);
      if (last.lengthInBytes <= maxBytes) return CompressedPhoto(last, w, h, q);
    }
    if (long <= 640) return CompressedPhoto(last!, w, h, kQualities.last);
    long = (long * 0.8).round();
  }
}
