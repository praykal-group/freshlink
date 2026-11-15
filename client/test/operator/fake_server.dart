import 'package:dio/dio.dart';

import '../helpers.dart';

/// A scripted I-CCMS backend for the operator flows: idempotent `/sync` (like SyncService),
/// presign + S3 PUT, grading, storage, label, operator reads. `online = false` drops every call.
class FakeIccmsServer {
  bool online = true;
  bool gradeModelMissing = false;
  final applied = <String, Map<String, dynamic>>{};
  final appliedOrder = <String>[];
  final syncCalls = <List<Map<String, dynamic>>>[];
  final uploads = <String>[];
  final gradeCalls = <String>[];
  final storageAssigned = <String, String>{};
  int presigns = 0;
  late final FakeAdapter adapter = FakeAdapter(_handle);

  static const siteId = 'site-dck';
  static const rohuId = 'p-rohu';

  Map<String, dynamic> get masters => {
        'products': [
          {'id': rohuId, 'code': 'ROHU', 'name': 'Rohu', 'nameHi': 'रोहू', 'nameMr': 'रोहू', 'category': 'FISH', 'isClimacteric': false, 'safeTempMin': '0', 'safeTempMax': '4'},
          {'id': 'p-banana', 'code': 'BANANA', 'name': 'Banana', 'nameHi': 'केला', 'nameMr': 'केळी', 'category': 'PRODUCE', 'isClimacteric': true, 'safeTempMin': '13', 'safeTempMax': '15'},
        ],
        'sites': [
          {'id': siteId, 'code': 'DCK-PTN', 'name': 'Paithan Dock', 'type': 'DOCK'},
        ],
        'storageUnits': [
          {'id': 'u-bc1', 'siteId': siteId, 'code': 'BC-1', 'type': 'BLAST_CHILLER', 'tempMin': '-2', 'tempMax': '4', 'capacityKg': '2000', 'usedKg': '100'},
        ],
        'config': {},
      };

  List<String> get appliedTypes => [for (final id in appliedOrder) applied[id]!['type'] as String];

  (int, Object?) _handle(String method, String path, RequestOptions o) {
    if (!online) return (0, null);
    if (o.uri.host == 's3.test') {
      uploads.add(o.uri.path);
      return (200, null);
    }
    final batch = RegExp(r'^/batches/([^/]+)/(grade|storage-path|storage|label)$').firstMatch(path);
    if (batch != null) {
      final id = batch.group(1)!;
      final known = applied.values.any((op) => op['type'] == 'BATCH_CREATE' && op['payload']['id'] == id);
      if (!known) return (404, envelope('NOT_FOUND', 'Batch not found'));
      switch (batch.group(2)) {
        case 'grade':
          gradeCalls.add(id);
          if (gradeModelMissing) return (503, envelope('MODEL_UNAVAILABLE', 'No vision model registered'));
          return (200, {
            'id': 'g-$id', 'batchId': id, 'grade': 'A', 'confidence': 0.91, 'defects': [],
            'storagePath': {'path': 'BLAST_CHILLER', 'sellFirst': false, 'recommendedUnit': {'id': 'u-bc1', 'code': 'BC-1', 'type': 'BLAST_CHILLER', 'freeKg': 1900}, 'alternatives': []},
          });
        case 'storage-path':
          return (200, {'path': 'BLAST_CHILLER', 'sellFirst': false, 'recommendedUnit': {'id': 'u-bc1', 'code': 'BC-1', 'type': 'BLAST_CHILLER', 'freeKg': 1900}, 'alternatives': []});
        case 'storage':
          storageAssigned[id] = (o.data as Map)['storageUnitId'] as String;
          return (200, {'id': id, 'status': 'STORED'});
        case 'label':
          return (200, {
            'code': 'FSH-20261115-DCK-PTN-0001', 'product': {'code': 'ROHU', 'name': 'Rohu'}, 'weightKg': 120, 'grade': 'A',
            'caughtOrHarvestedAt': '2026-11-15T03:00:00.000Z', 'sourceSite': {'code': 'DCK-PTN', 'name': 'Paithan Dock'},
            'traceUrl': 'https://api.test/t/FSH-20261115-DCK-PTN-0001?s=abc', 'qrData': 'https://api.test/t/FSH-20261115-DCK-PTN-0001?s=abc',
          });
      }
    }
    switch (path) {
      case '/me/session':
        return (200, {'ok': true});
      case '/me':
        return (200, meJson('OPERATOR'));
      case '/masters/bundle':
        return (200, masters);
      case '/operator/summary':
        return (200, {'site': {'name': 'Paithan Dock'}, 'registered': applied.values.where((o) => o['type'] == 'BATCH_CREATE').length, 'graded': gradeCalls.length, 'stored': 0, 'dispatched': 0});
      case '/operator/trips':
        return (200, {
          'date': '2026-11-15',
          'items': [
            {
              'id': 'trip-1', 'code': 'TRP-20261115-0001', 'status': 'ASSIGNED', 'plannedStart': '2026-11-15T01:30:00.000Z',
              'vehicle': {'regNo': 'MH20-RF-1001', 'capacityKg': 3000}, 'driverName': 'Ravindra Shankar Deshmukh',
              'allocated': [
                {'id': 'b-1', 'code': 'FSH-20261115-DCK-PTN-0001', 'weightKg': 120},
                {'id': 'b-2', 'code': 'FSH-20261115-DCK-PTN-0002', 'weightKg': 80},
              ],
              'loadedBatchIds': [],
            },
          ],
        });
      case '/files/presign':
        presigns++;
        return (200, {'uploadUrl': 'https://s3.test/put/$presigns', 'key': 'BATCH_IMAGE/2026/11/$presigns.jpg', 'headers': {'Content-Type': 'image/jpeg'}, 'expiresIn': 300});
      case '/sync':
        final ops = [for (final x in (o.data as Map)['ops'] as List) Map<String, dynamic>.from(x as Map)];
        syncCalls.add(ops);
        return (200, {
          'results': [
            for (final op in ops)
              if (applied.containsKey(op['clientOpId']))
                {'clientOpId': op['clientOpId'], 'type': op['type'], 'status': 'APPLIED', 'replayed': true}
              else ...[
                () {
                  applied[op['clientOpId'] as String] = op;
                  appliedOrder.add(op['clientOpId'] as String);
                  return {'clientOpId': op['clientOpId'], 'type': op['type'], 'status': 'APPLIED'};
                }(),
              ],
          ],
        });
    }
    return (404, envelope('NOT_FOUND', 'No route $method $path'));
  }
}
