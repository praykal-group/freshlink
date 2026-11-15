import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iccms/apps/operator/data/models.dart';
import 'package:iccms/core/media/photo_compress.dart';
import 'package:iccms/core/printing/label_printer.dart';
import 'package:iccms/core/tags/tag_reader.dart';
import 'package:iccms/core/tags/wedge_tag_reader.dart';
import 'package:iccms/core/voice/voice_number.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tags (FO-FR-05)', () {
    test('NFC UID bytes → upper-case hex', () {
      expect(nfcUid([0x04, 0xa1, 0xb2, 0xc3, 0xd4, 0xe5, 0xf6]), '04A1B2C3D4E5F6');
    });

    test('QR with an I-CCMS trace URL → the batch code; other values kept; invalid → null', () {
      expect(normaliseTagValue(TagKind.qr, 'https://api.iccms.in/t/FSH-20261115-DCK-PTN-0007?s=abc'), 'FSH-20261115-DCK-PTN-0007');
      expect(normaliseTagValue(TagKind.qr, 'CRATE-0042'), 'CRATE-0042');
      expect(normaliseTagValue(TagKind.qr, 'has spaces!'), isNull);
      expect(normaliseTagValue(TagKind.uhf, 'e200 3412 0123'), 'E20034120123');
      expect(normaliseTagValue(TagKind.nfc, 'ab'), isNull, reason: 'shorter than the server minimum (4)');
    });

    test('RFID keyboard wedge: fast keystrokes ending in Enter; a long pause starts over', () {
      final w = WedgeBuffer();
      final t0 = DateTime(2026, 11, 15, 9);
      for (var i = 0; i < 'e2003412'.length; i++) {
        w.add('e2003412'[i], t0.add(Duration(milliseconds: 10 * i)));
      }
      expect(w.submit(), 'E2003412');
      w.add('ZZZZ', t0);
      w.add('E2003413', t0.add(const Duration(seconds: 2))); // stale chars dropped
      expect(w.submit(), 'E2003413');
      expect(w.submit(), isNull);
    });
  });

  group('photos (FO-NFR-04: 1280 px long side, < 500 KB)', () {
    test('target size keeps the aspect ratio and never upscales', () {
      expect(targetSize(4000, 3000), (1280, 960));
      expect(targetSize(3000, 4000), (960, 1280));
      expect(targetSize(800, 600), (800, 600));
    });

    test('quality steps down until the photo is under 500 KB', () async {
      final calls = <int>[];
      // Fake encoder: size grows with quality (~522 KB at q85, ~460 KB at q75 for 1280×960).
      Future<Uint8List> encoder(Uint8List s, {required int width, required int height, required int quality}) async {
        calls.add(quality);
        return Uint8List((width * height * quality / 200).round());
      }

      final r = await compressPhoto(Uint8List(10), 4032, 3024, encode: encoder);
      expect(r.width, 1280);
      expect(r.height, 960);
      expect(r.bytes.lengthInBytes, lessThanOrEqualTo(500 * 1024));
      expect(r.quality, 75);
      expect(calls, [85, 75]);
    });

    test('a very noisy photo is shrunk further rather than sent over 500 KB', () async {
      Future<Uint8List> stubborn(Uint8List s, {required int width, required int height, required int quality}) async => Uint8List(width * height);
      final r = await compressPhoto(Uint8List(10), 4032, 3024, encode: stubborn);
      expect(r.bytes.lengthInBytes, lessThanOrEqualTo(500 * 1024));
      expect(r.width, lessThan(1280));
    });
  });

  group('voice numbers', () {
    test('digits, decimal words and Devanagari digits in EN / HI / MR', () {
      expect(parseSpokenNumber('12.5'), 12.5);
      expect(parseSpokenNumber('twelve point five'), isNull, reason: 'number words are not parsed; recognisers return digits');
      expect(parseSpokenNumber('12 point 5'), 12.5);
      expect(parseSpokenNumber('१२ दशमलव ५'), 12.5);
      expect(parseSpokenNumber('२४०'), 240);
      expect(parseSpokenNumber('वजन 1 2 0 किलो'), 120);
      expect(parseSpokenNumber('minus 1.5'), -1.5);
      expect(parseSpokenNumber('उणे २'), -2);
      expect(parseSpokenNumber('3,5'), 3.5);
      expect(parseSpokenNumber('hello'), isNull);
    });
  });

  group('storage path offline preview = server rule (SYN-10)', () {
    const rohu = Product(id: 'p1', code: 'ROHU', name: 'Rohu', nameHi: 'रोहू', nameMr: 'रोहू', category: 'FISH', isClimacteric: false, safeTempMin: 0, safeTempMax: 4);
    const banana = Product(id: 'p2', code: 'BANANA', name: 'Banana', nameHi: 'केला', nameMr: 'केळी', category: 'PRODUCE', isClimacteric: true, safeTempMin: 13, safeTempMax: 15);
    final units = [
      const StorageUnit(id: 'u1', siteId: 's', code: 'BC-1', type: 'BLAST_CHILLER', tempMin: -2, tempMax: 4, capacityKg: 1000, usedKg: 900),
      const StorageUnit(id: 'u2', siteId: 's', code: 'BC-2', type: 'BLAST_CHILLER', tempMin: -2, tempMax: 4, capacityKg: 1000, usedKg: 100),
      const StorageUnit(id: 'u3', siteId: 's', code: 'RC-1', type: 'RIPENING_CHAMBER', tempMin: 12, tempMax: 18, capacityKg: 2000, usedKg: 0),
      const StorageUnit(id: 'u4', siteId: 's', code: 'CR-1', type: 'COLD_ROOM', tempMin: 0, tempMax: 8, capacityKg: 500, usedKg: 0),
    ];
    test('fish → blast chiller with room; climacteric → ripening; grade C → cold room + sell first', () {
      final f = localStoragePath(rohu, 'A', units, 200);
      expect([f.path, f.recommended?.code, f.offline], ['BLAST_CHILLER', 'BC-2', true]);
      expect(localStoragePath(banana, 'B', units, 300).recommended?.code, 'RC-1');
      final c = localStoragePath(rohu, 'C', units, 50);
      expect([c.path, c.sellFirst, c.recommended?.code], ['COLD_ROOM', true, 'CR-1']);
      expect(localStoragePath(rohu, null, units, 5000).recommended, isNull);
    });
  });

  test('ESC/POS label: code, product and a QR of the trace URL', () async {
    final bytes = await labelBytes(LabelData(
      code: 'FSH-20261115-DCK-PTN-0007', productName: 'Rohu', weightKg: 120, grade: 'A',
      caughtOrHarvestedAt: DateTime.utc(2026, 11, 15, 4), sourceSite: 'Paithan Dock', qrData: 'https://api.iccms.in/t/FSH-20261115-DCK-PTN-0007?s=x',
    ));
    final text = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
    expect(text, contains('FSH-20261115-DCK-PTN-0007'));
    expect(text, contains('Rohu'));
    expect(text, contains('Grade A'));
    expect(text, contains('https://api.iccms.in/t/FSH-20261115-DCK-PTN-0007?s=x'), reason: 'QR payload is sent to the printer');
    expect(bytes.sublist(bytes.length - 4), isNotEmpty);
  });
}
