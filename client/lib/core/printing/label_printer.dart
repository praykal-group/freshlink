import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

/// What goes on a batch label (`GET /batches/:id/label`).
class LabelData {
  const LabelData({required this.code, required this.productName, required this.weightKg, this.grade, required this.caughtOrHarvestedAt, required this.sourceSite, required this.qrData});

  factory LabelData.fromJson(Map<String, dynamic> j) => LabelData(
        code: j['code'] as String,
        productName: (j['product'] as Map)['name'] as String,
        weightKg: (j['weightKg'] as num).toDouble(),
        grade: j['grade'] as String?,
        caughtOrHarvestedAt: DateTime.parse(j['caughtOrHarvestedAt'] as String),
        sourceSite: (j['sourceSite'] as Map)['name'] as String,
        qrData: j['qrData'] as String,
      );

  final String code;
  final String productName;
  final double weightKg;
  final String? grade;
  final DateTime caughtOrHarvestedAt;
  final String sourceSite;

  /// Signed trace URL (SYN-09): the QR opens the public trace page.
  final String qrData;
}

String _date(DateTime d) {
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}-${two(l.month)}-${l.year} ${two(l.hour)}:${two(l.minute)}';
}

/// ESC/POS bytes for a 58 mm thermal printer (FO-FR-09): product, code, weight, grade, origin,
/// catch/harvest time and the QR. Latin text only (printer fonts); the QR carries the rest.
Future<List<int>> labelBytes(LabelData d, {CapabilityProfile? profile, PaperSize paper = PaperSize.mm58}) async {
  final g = Generator(paper, profile ?? await CapabilityProfile.load());
  return [
    ...g.reset(),
    ...g.text('I-CCMS', styles: const PosStyles(align: PosAlign.center, bold: true)),
    ...g.text(d.productName, styles: const PosStyles(align: PosAlign.center, height: PosTextSize.size2, width: PosTextSize.size2, bold: true)),
    ...g.text(d.code, styles: const PosStyles(align: PosAlign.center, bold: true)),
    ...g.hr(),
    ...g.row([
      PosColumn(text: '${d.weightKg.toStringAsFixed(1)} kg', width: 6),
      PosColumn(text: d.grade == null ? 'Grade -' : 'Grade ${d.grade}', width: 6, styles: const PosStyles(align: PosAlign.right, bold: true)),
    ]),
    ...g.text(d.sourceSite),
    ...g.text(_date(d.caughtOrHarvestedAt)),
    ...g.feed(1),
    ...g.qrcode(d.qrData, size: QRSize.size5, cor: QRCorrection.M),
    ...g.text('Scan to trace', styles: const PosStyles(align: PosAlign.center)),
    ...g.feed(3),
    ...g.cut(),
  ];
}

/// Bluetooth thermal printer (paired in Android settings first; the printer setup screen picks one).
class BluetoothLabelPrinter {
  const BluetoothLabelPrinter();

  Future<List<BluetoothInfo>> paired() async {
    if (!await PrintBluetoothThermal.bluetoothEnabled) return const [];
    return PrintBluetoothThermal.pairedBluetooths;
  }

  Future<bool> connect(String mac) async {
    if (await PrintBluetoothThermal.connectionStatus) return true;
    return PrintBluetoothThermal.connect(macPrinterAddress: mac);
  }

  Future<bool> print(String mac, List<int> bytes) async {
    if (!await connect(mac)) return false;
    return PrintBluetoothThermal.writeBytes(bytes);
  }
}
