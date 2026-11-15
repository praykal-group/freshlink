import 'package:dio/dio.dart';

import '../helpers.dart';

/// A scripted I-CCMS backend for the driver flows (M12): the trip, pre-check / start, cargo,
/// route proposals, alerts, presign + S3 PUT, and an idempotent `/sync` that applies the driver
/// ops to the trip like SyncService does. `online = false` drops every call.
class FakeDriverServer {
  bool online = true;
  String status = 'ASSIGNED';
  int routeVersion = 1;
  Map<String, dynamic>? pending; // a proposed route (server JSON)
  final alerts = <Map<String, dynamic>>[];
  final applied = <String, Map<String, dynamic>>{};
  final appliedOrder = <String>[];
  final syncCalls = <List<Map<String, dynamic>>>[];
  final uploads = <String>[];
  final calls = <String>[];
  int presigns = 0;
  late final FakeAdapter adapter = FakeAdapter(_handle);

  static const tripId = '9a8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b';
  static const dropId = '1b8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b';
  static const b1 = '0f8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a71';
  static const b2 = '0f8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a72';

  final stops = <Map<String, dynamic>>[
    {'id': 'pick-1', 'seq': 1, 'type': 'PICKUP', 'lat': 19.476, 'lng': 75.383, 'status': 'COMPLETED', 'site': {'code': 'DCK-PTN', 'name': 'Paithan Dock'}, 'batchIds': null},
    {'id': dropId, 'seq': 2, 'type': 'DROP', 'orderId': 'o1', 'lat': 19.8762, 'lng': 75.3433, 'status': 'PENDING', 'eta': '2026-11-15T04:10:00Z', 'windowStart': '2026-11-15T03:30:00Z', 'windowEnd': '2026-11-15T05:00:00Z', 'site': {'code': 'DC-CSN', 'name': 'Sambhajinagar DC'}, 'batchIds': [b1, b2]},
  ];

  List<String> get appliedTypes => [for (final id in appliedOrder) applied[id]!['type'] as String];

  Map<String, dynamic> get trip => {
        'id': tripId, 'code': 'TRP-20261115-0001', 'status': status, 'plannedStart': '2026-11-15T01:30:00Z', 'currentRouteVersion': routeVersion,
        'vehicle': {'id': 'veh-1', 'regNo': 'MH20-RF-1001', 'capacityKg': 3000},
        'stops': stops,
        'batches': [
          {'batchId': b1, 'code': 'FSH-20261115-DCK-PTN-0001', 'weightKg': 120, 'status': 'IN_TRANSIT', 'currentGrade': 'A', 'product': {'code': 'ROHU', 'name': 'Rohu', 'nameHi': 'रोहू'}, 'tagUids': ['04A1B2C3D4E5F6']},
          {'batchId': b2, 'code': 'FSH-20261115-DCK-PTN-0002', 'weightKg': 80, 'status': 'IN_TRANSIT', 'currentGrade': 'B', 'product': {'code': 'ROHU', 'name': 'Rohu'}, 'tagUids': ['04FFEE0011']},
        ],
      };

  /// What the incident engine does on a diversion (M9): a new version with a buyer drop.
  void proposeDiversion() {
    pending = {
      'version': 2, 'reason': 'DIVERSION', 'status': 'PROPOSED', 'distanceKm': 131.3, 'extraKm': 11.2, 'canDecline': false,
      'stopRows': [
        {'id': 'pick-1', 'seq': 1, 'type': 'PICKUP', 'lat': 19.476, 'lng': 75.383, 'status': 'COMPLETED', 'site': {'code': 'DCK-PTN', 'name': 'Paithan Dock'}},
        {'id': 'div-1', 'seq': 2, 'type': 'DIVERSION_DROP', 'lat': 19.8347, 'lng': 75.8816, 'status': 'PENDING', 'eta': '2026-11-15T04:40:00Z', 'buyer': {'name': 'Jalna Fresh Traders'}},
      ],
    };
  }

  (int, Object?) _handle(String method, String path, RequestOptions o) {
    if (!online) return (0, null);
    calls.add('$method $path');
    if (o.uri.host == 's3.test') {
      uploads.add(o.uri.path);
      return (200, null);
    }
    switch (path) {
      case '/me/session':
        return (200, {'ok': true});
      case '/me':
        return (200, meJson('DRIVER'));
      case '/masters/bundle':
        return (200, {'products': [], 'sites': [], 'storageUnits': [], 'config': {'gpsIntervalSec': 30}});
      case '/driver/trips/current':
        return (200, trip);
      case '/driver/trips':
        return (200, {'items': [{'id': tripId, 'code': 'TRP-20261115-0001', 'status': status, 'plannedStart': '2026-11-15T01:30:00Z', 'podStops': 0}], 'nextCursor': null});
      case '/alerts':
        return (200, {'items': [for (final a in alerts) if (a['status'] == 'OPEN') a], 'nextCursor': null});
      case '/files/presign':
        presigns++;
        return (200, {'uploadUrl': 'https://s3.test/put/$presigns', 'key': 'POD/2026/11/$presigns.bin', 'headers': {'Content-Type': 'application/octet-stream'}, 'expiresIn': 300});
      case '/trips/$tripId/pre-check':
        final sp = ((o.data as Map)['setpointC'] as num).toDouble();
        if (sp < 0 || sp > 4) return (422, {'error': {'code': 'PRE_CHECK_FAILED', 'message': 'Pre-trip check failed', 'details': {'problems': ['SETPOINT_OUT_OF_RANGE'], 'allowed': {'min': 0, 'max': 4}}}});
        status = 'PRE_CHECK_DONE';
        return (200, {'tripId': tripId, 'status': status});
      case '/trips/$tripId/start':
        if (status != 'PRE_CHECK_DONE') return (409, envelope('PRE_CHECK_REQUIRED'));
        status = 'IN_PROGRESS';
        return (200, {'id': tripId, 'status': status});
      case '/trips/$tripId/cargo-status':
        return (200, {
          'tripId': tripId,
          'telemetry': {'tempC': 2.4, 'humidityPct': 91, 'ts': '2026-11-15T04:00:00Z'},
          'batches': [
            {'batchId': b1, 'code': 'FSH-20261115-DCK-PTN-0001', 'product': {'code': 'ROHU', 'name': 'Rohu', 'safeTempMin': 0, 'safeTempMax': 4}, 'grade': 'A', 'weightKg': 120, 'remainingShelfLifeH': 52.5},
            {'batchId': b2, 'code': 'FSH-20261115-DCK-PTN-0002', 'product': {'code': 'ROHU', 'name': 'Rohu', 'safeTempMin': 0, 'safeTempMax': 4}, 'grade': 'B', 'weightKg': 80, 'remainingShelfLifeH': 30},
          ],
        });
      case '/trips/$tripId/route':
        return (200, {'currentVersion': routeVersion, 'accepted': {'version': routeVersion, 'distanceKm': 120.0, 'stopRows': stops}, 'pending': pending});
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
                  _apply(op);
                  return {'clientOpId': op['clientOpId'], 'type': op['type'], 'status': 'APPLIED'};
                }(),
              ],
          ],
        });
    }
    return (404, envelope('NOT_FOUND', 'No route $method $path'));
  }

  void _apply(Map<String, dynamic> op) {
    final p = Map<String, dynamic>.from(op['payload'] as Map);
    switch (op['type']) {
      case 'STOP_ARRIVE':
        stops.firstWhere((s) => s['id'] == p['stopId'])['status'] = 'ARRIVED';
      case 'POD':
        stops.firstWhere((s) => s['id'] == p['stopId'])['status'] = 'COMPLETED';
      case 'ALERT_ACK':
        alerts.firstWhere((a) => a['id'] == p['alertId'])['status'] = 'ACKNOWLEDGED';
      case 'ROUTE_ACCEPT':
        final rows = List<Map<String, dynamic>>.from((pending!['stopRows'] as List).map((s) => Map<String, dynamic>.from(s as Map)));
        stops
          ..clear()
          ..addAll(rows);
        routeVersion = (p['version'] as num).toInt();
        pending = null;
    }
  }
}
