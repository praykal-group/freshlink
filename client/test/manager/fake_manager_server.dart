import 'package:dio/dio.dart';

import '../helpers.dart';

/// A scripted control-tower backend (M13). It applies planning writes like the real services:
/// run → DRAFT orders, PATCH edits a DRAFT, approve → APPROVED, build routes → PLANNED trips,
/// assign → ASSIGNED. `role` decides the `/me` answer; ADMIN-only routes return 403 otherwise.
class FakeManagerServer {
  FakeManagerServer({this.role = 'MANAGER'});
  String role;
  final calls = <String>[];
  final bodies = <String, Object?>{};
  late final FakeAdapter adapter = FakeAdapter(_handle);

  int criticalAlerts = 1;
  final alerts = <Map<String, dynamic>>[
    {'id': 'al-1', 'type': 'TEMP_EXCURSION', 'severity': 'CRITICAL', 'status': 'OPEN', 'message': 'Reefer at 9.1 °C on TRP-20261115-0001', 'tripId': 't-1', 'createdAt': '2026-11-15T04:00:00Z'},
  ];
  final orders = <Map<String, dynamic>>[];
  final builtTrips = <Map<String, dynamic>>[];
  final assigned = <String, Map<String, dynamic>>{};

  static const dc = 's-dc';
  static const dock = 's-dock';
  static const rohu = 'p-rohu';

  final forecast = [
    for (var i = 0; i < 7; i++) {'siteId': dc, 'productId': rohu, 'date': '2026-11-${16 + i}', 'predictedKg': 400 + i * 25, 'lowerKg': 340 + i * 25, 'upperKg': 470 + i * 25, 'modelVersion': 'ensemble-v3', 'runId': 'r1'},
  ];

  final telemetry = {
    'band': {'tempMin': 0, 'tempMax': 4},
    'points': [
      for (var i = 0; i < 12; i++) {'at': DateTime.utc(2026, 11, 15, 3, i * 5).toIso8601String(), 'temp_c': i == 7 ? 6.2 : 2.0 + (i % 3) * 0.4, 'humidity_pct': 90},
    ],
  };

  (int, Object?) _handle(String method, String path, RequestOptions o) {
    calls.add('$method $path');
    bodies['$method $path'] = o.data;
    if (path.startsWith('/admin/') && role != 'ADMIN') return (403, envelope('FORBIDDEN_ROLE', 'Admins only'));
    final order = RegExp(r'^/orders/([^/]+)(/approve)?$').firstMatch(path);
    if (order != null) {
      final o2 = orders.firstWhere((x) => x['id'] == order.group(1));
      if (order.group(2) != null) {
        o2['status'] = 'APPROVED';
        return (200, {...o2, 'allocatedKg': o2['quantityKg'], 'shortfallKg': 0});
      }
      final b = Map<String, dynamic>.from(o.data as Map);
      if (b['quantityKg'] != null) o2['quantityKg'] = b['quantityKg'];
      return (200, o2);
    }
    final assign = RegExp(r'^/trips/([^/]+)/assign$').firstMatch(path);
    if (assign != null) {
      assigned[assign.group(1)!] = Map<String, dynamic>.from(o.data as Map);
      return (200, {'id': assign.group(1), 'status': 'ASSIGNED'});
    }
    switch (path) {
      case '/me/session':
        return (200, {'ok': true});
      case '/me':
        return (200, meJson(role, name: 'Asha'));
      case '/masters/bundle':
        return (200, {
          'products': [{'id': rohu, 'code': 'ROHU', 'name': 'Rohu', 'nameHi': 'रोहू', 'nameMr': 'रोहू', 'category': 'FISH'}],
          'sites': [
            {'id': dc, 'code': 'DC-CSN', 'name': 'Sambhajinagar DC', 'type': 'DISTRIBUTION_CENTRE'},
            {'id': dock, 'code': 'DCK-PTN', 'name': 'Paithan Dock', 'type': 'DOCK'},
          ],
          'storageUnits': [],
          'config': {},
        });
      case '/control/summary':
        return (200, {
          'date': '2026-11-15',
          'kpis': {'activeTrips': 2, 'openCriticalAlerts': criticalAlerts, 'atRiskBatches': 3, 'deliveriesToday': 5, 'spoilageAvoidedKg': 640.5},
          'vehicles': [
            {'vehicleId': 'v1', 'regNo': 'MH20-RF-1001', 'tripId': 't-1', 'tripCode': 'TRP-20261115-0001', 'driverName': 'Ravi', 'lat': 19.70, 'lng': 75.36, 'tempC': 6.2, 'at': '2026-11-15T04:00:00Z'},
            {'vehicleId': 'v2', 'regNo': 'MH20-RF-1002', 'tripId': 't-2', 'tripCode': 'TRP-20261115-0002', 'driverName': null, 'lat': null, 'lng': null, 'tempC': null, 'at': null},
          ],
        });
      case '/control/drivers':
        return (200, {'items': [{'id': 'd-1', 'name': 'Ravi Deshmukh', 'phone': '+919800000001', 'busyTripCode': null}, {'id': 'd-2', 'name': 'Sunil Pawar', 'phone': '+919800000002', 'busyTripCode': 'TRP-20261115-0001'}]});
      case '/masters/vehicles':
        return (200, [{'id': 'v3', 'regNo': 'MH20-RF-1003', 'capacityKg': 3000, 'active': true}]);
      case '/alerts':
        return (200, {'items': alerts, 'nextCursor': null});
      case '/incidents':
        return (200, {'items': [{'id': 'inc-1', 'tripId': 't-1', 'kind': 'TEMP_DRIFT', 'status': 'ACTION_IN_PROGRESS', 'decidedAction': 'DRIVER_FIX', 'steps': 2, 'createdAt': '2026-11-15T04:01:00Z'}], 'nextCursor': null});
      case '/incidents/inc-1':
        return (200, {
          'id': 'inc-1', 'tripId': 't-1', 'kind': 'TEMP_DRIFT', 'status': 'ACTION_IN_PROGRESS', 'decidedAction': 'DRIVER_FIX', 'trip': {'code': 'TRP-20261115-0001'}, 'rescueTrip': null,
          'decisionLog': [
            {'at': '2026-11-15T04:01:00Z', 'step': 'CLASSIFIED', 'reason': 'reefer on, slow drift'},
            {'at': '2026-11-15T04:01:01Z', 'step': 'DRIVER_FIX', 'reason': 'driver instructed to fix'},
          ],
          'offers': [{'id': 'of-1', 'status': 'EXPIRED', 'quantityKg': 120, 'createdAt': '2026-11-15T04:02:00Z', 'buyer': {'name': 'Jalna Fresh Traders', 'type': 'LOCAL_MARKET'}}],
        });
      case '/trips':
        return (200, {'items': [
          {'id': 't-1', 'code': 'TRP-20261115-0001', 'status': 'IN_PROGRESS', 'plannedStart': '2026-11-15T01:30:00Z', 'vehicle': {'regNo': 'MH20-RF-1001'}, 'driver': {'name': 'Ravi'}},
          {'id': 't-9', 'code': 'TRP-20261115-0009', 'status': 'PLANNED', 'plannedStart': '2026-11-15T05:30:00Z', 'vehicle': {'regNo': 'MH20-RF-1003'}, 'driver': null},
        ], 'nextCursor': null});
      case '/trips/t-1':
        return (200, {
          'id': 't-1', 'code': 'TRP-20261115-0001', 'status': 'IN_PROGRESS', 'plannedStart': '2026-11-15T01:30:00Z', 'startedAt': '2026-11-15T03:00:00Z', 'distanceKm': 120.4, 'co2Kg': null,
          'vehicle': {'regNo': 'MH20-RF-1001'}, 'driver': {'name': 'Ravi'},
          'stops': [
            {'id': 'st-1', 'seq': 1, 'type': 'PICKUP', 'status': 'COMPLETED', 'site': {'name': 'Paithan Dock'}},
            {'id': 'st-2', 'seq': 2, 'type': 'DROP', 'status': 'PENDING', 'eta': '2026-11-15T05:00:00Z', 'site': {'name': 'Sambhajinagar DC'}},
          ],
          'batches': [{'batchId': 'b1', 'code': 'FSH-20261115-DCK-PTN-0001', 'weightKg': 120, 'status': 'IN_TRANSIT', 'product': {'name': 'Rohu'}}],
        });
      case '/trips/t-1/route':
        return (200, {'currentVersion': 1, 'accepted': {'version': 1}, 'pending': null});
      case '/trips/t-1/telemetry':
        return (200, telemetry);
      case '/forecasts':
        return (200, forecast);
      case '/planning/run':
        orders
          ..clear()
          ..addAll([
            {'id': 'o-1', 'code': 'ORD-20261116-0001', 'status': 'DRAFT', 'productId': rohu, 'sourceSiteId': dock, 'destinationSiteId': dc, 'quantityKg': 420},
            {'id': 'o-2', 'code': 'ORD-20261116-0002', 'status': 'DRAFT', 'productId': rohu, 'sourceSiteId': dock, 'destinationSiteId': dc, 'quantityKg': 180},
          ]);
        return (200, {
          'date': (o.data as Map)['date'], 'replacedDrafts': 0, 'orders': orders,
          'needs': [{'siteCode': 'DC-CSN', 'productCode': 'ROHU', 'forecastKg': 650, 'onHandKg': 50, 'inTransitKg': 0, 'needKg': 600, 'shortfallKg': 0}],
        });
      case '/orders':
        return (200, {'items': orders, 'nextCursor': null});
      case '/planning/routes':
        for (final o2 in orders.where((x) => x['status'] == 'APPROVED')) {
          o2['status'] = 'PLANNED';
        }
        builtTrips
          ..clear()
          ..add({'id': 't-new', 'code': 'TRP-20261116-0001', 'status': 'PLANNED', 'distanceKm': 52.3, 'loadKg': 600, 'stops': [{}, {}, {}]});
        return (200, {'date': (o.data as Map)['date'], 'depotSiteId': dock, 'trips': builtTrips, 'optimiser': {'feasible': true}});
      case '/edit-requests':
        return (200, {'items': [{'id': 'er-1', 'batch': {'code': 'FSH-20261115-DCK-PTN-0004'}, 'requester': {'name': 'Meena'}, 'changes': {'weightKg': 95}, 'reason': 'scale was off', 'createdAt': '2026-11-15T02:00:00Z'}], 'nextCursor': null});
      case '/grades/disputes':
        return (200, {'items': [{'id': 'g-1', 'batch': {'code': 'FSH-20261115-DCK-PTN-0005'}, 'grade': 'C', 'confidence': 0.62, 'disputeReason': 'gills are bright red'}], 'nextCursor': null});
      case '/buyers':
        if (method == 'POST') return (201, {'id': 'by-new', ...Map<String, dynamic>.from(o.data as Map)});
        return (200, {'items': [{'id': 'by-1', 'name': 'Jalna Fresh Traders', 'type': 'LOCAL_MARKET', 'minGrade': 'B', 'discountPct': 20, 'acceptedProductIds': [rohu], 'openingHours': {'mon': [['06:00', '20:00']]}, 'lat': 19.83, 'lng': 75.88, 'phone': '+919811111111'}], 'nextCursor': null});
      case '/admin/users':
        return (200, {'items': [{'id': 'u-1', 'name': 'Ravi Deshmukh', 'role': 'DRIVER', 'status': 'ACTIVE', 'phone': '+919800000001', 'siteId': dock, 'language': 'mr'}], 'nextCursor': null});
      case '/reports/reefer-health':
        return (200, [{'regNo': 'MH20-RF-1001', 'baselinePulldownRate': 0.8, 'flagged': true, 'weeks': [{'degradationPct': 22.5, 'flagged': true}]}]);
      case '/control/releases':
        return (200, {'items': []});
    }
    if (path.startsWith('/config/')) return method == 'PUT' ? (200, {'ok': true}) : (200, {'key': path.substring(8), 'value': 5});
    return (404, envelope('NOT_FOUND', 'No route $method $path'));
  }
}
