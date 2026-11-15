import 'dart:convert';
import 'dart:io';

import 'gps_fix.dart';

/// Hand-off file between the foreground-service isolate (the only writer) and the app (the only
/// reader) (DA-FR-10, DA-NFR-01). The service appends one JSON line per fix; the app [drain]s by
/// renaming the file first, so appends during a drain go to a fresh file and nothing is lost or
/// read twice. A crash after the outbox write but before the delete re-reads the same points;
/// the server writes them to InfluxDB by timestamp, so a replay overwrites instead of duplicating.
class GpsJournal {
  GpsJournal(this.dir);

  final Directory dir;

  File get _live => File('${dir.path}/gps.jsonl');
  File get _draining => File('${dir.path}/gps.draining.jsonl');

  /// Called from the service isolate. Flushes so a killed process keeps what it reported.
  Future<void> append(GpsFix fix) async {
    await dir.create(recursive: true);
    await _live.writeAsString('${jsonEncode(fix.toJson())}\n', mode: FileMode.append, flush: true);
  }

  /// Takes every journalled fix, oldest first. [consume] stores them (outbox); the file is deleted
  /// only after it returns, so a failure leaves them for the next drain.
  Future<int> drain(Future<void> Function(List<GpsFix> fixes) consume) async {
    // A previous drain that failed left its file behind: finish that one first.
    if (!await _draining.exists()) {
      if (!await _live.exists()) return 0;
      await _live.rename(_draining.path);
    }
    final fixes = <GpsFix>[];
    for (final line in await _draining.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        final f = GpsFix.tryParse(jsonDecode(line));
        if (f != null) fixes.add(f);
      } on FormatException {
        // a line cut by a killed process: skip it, keep the rest
      }
    }
    fixes.sort((a, b) => a.at.compareTo(b.at));
    if (fixes.isNotEmpty) await consume(fixes);
    await _draining.delete();
    return fixes.length;
  }
}
