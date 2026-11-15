import '../../../core/map/corridor.dart';

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
double? _num(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

/// Local product name (EN / HI / MR) from a product JSON.
String productName(Map<String, dynamic>? p, String lang) {
  if (p == null) return '';
  final local = switch (lang) { 'hi' => p['nameHi'], 'mr' => p['nameMr'], _ => null };
  return (local as String?)?.isNotEmpty == true ? local! : (p['name'] as String? ?? p['code'] as String? ?? '');
}

enum StopKind { pickup, drop, diversionDrop, rescuePickup, rescueDrop, coldStorageDrop }

StopKind _stopKind(String? t) => switch (t) {
      'PICKUP' => StopKind.pickup,
      'DIVERSION_DROP' => StopKind.diversionDrop,
      'RESCUE_PICKUP' => StopKind.rescuePickup,
      'RESCUE_DROP' => StopKind.rescueDrop,
      'COLD_STORAGE_DROP' => StopKind.coldStorageDrop,
      _ => StopKind.drop,
    };

class TripStop {
  const TripStop({
    required this.id, required this.seq, required this.kind, required this.name, required this.lat, required this.lng, required this.status,
    this.siteCode, this.orderId, this.windowStart, this.windowEnd, this.eta, this.arrivedAt, this.completedAt, this.expectedBatchIds,
  });

  final String id;
  final int seq;
  final StopKind kind;
  final String name;
  final String? siteCode;
  final String? orderId;
  final double lat;
  final double lng;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final DateTime? eta;
  final DateTime? arrivedAt;
  final DateTime? completedAt;
  final String status; // PENDING | ARRIVED | COMPLETED | SKIPPED | CANCELLED

  /// Batches this drop expects; null = any batch on board (diversion / cold storage / rescue).
  final List<String>? expectedBatchIds;

  bool get isDrop => kind != StopKind.pickup && kind != StopKind.rescuePickup;
  bool get isOpen => status == 'PENDING' || status == 'ARRIVED';
  GeoPoint get point => GeoPoint(lat, lng);

  factory TripStop.fromJson(Map<String, dynamic> j) {
    final site = j['site'] as Map?;
    final buyer = j['buyer'] as Map?;
    return TripStop(
      id: j['id'] as String,
      seq: (j['seq'] as num).toInt(),
      kind: _stopKind(j['type'] as String?),
      name: (site?['name'] ?? buyer?['name'] ?? j['type'] ?? '') as String,
      siteCode: site?['code'] as String?,
      orderId: j['orderId'] as String?,
      lat: _num(j['lat'])!,
      lng: _num(j['lng'])!,
      windowStart: _date(j['windowStart']),
      windowEnd: _date(j['windowEnd']),
      eta: _date(j['eta']),
      arrivedAt: _date(j['arrivedAt']),
      completedAt: _date(j['completedAt']),
      status: j['status'] as String? ?? 'PENDING',
      expectedBatchIds: (j['batchIds'] as List?)?.cast<String>(),
    );
  }

  TripStop copyWith({String? status, DateTime? arrivedAt, DateTime? completedAt}) => TripStop(
        id: id, seq: seq, kind: kind, name: name, siteCode: siteCode, orderId: orderId, lat: lat, lng: lng, windowStart: windowStart, windowEnd: windowEnd, eta: eta,
        arrivedAt: arrivedAt ?? this.arrivedAt, completedAt: completedAt ?? this.completedAt, status: status ?? this.status, expectedBatchIds: expectedBatchIds,
      );
}

class TripBatch {
  const TripBatch({required this.id, required this.code, required this.weightKg, required this.status, this.grade, this.product, this.tagUids = const [], this.unloadedAt});

  final String id;
  final String code;
  final double weightKg;
  final String status;
  final String? grade;
  final Map<String, dynamic>? product;
  final List<String> tagUids;
  final DateTime? unloadedAt;

  bool get onBoard => unloadedAt == null && status != 'DELIVERED' && status != 'PARTIALLY_DELIVERED' && status != 'REJECTED';

  /// The server's PoD rule: the scan is one of the batch's tag UIDs or its code (label QR).
  bool matchesScan(String scanned) => scanned == code || tagUids.contains(scanned);

  factory TripBatch.fromJson(Map<String, dynamic> j) => TripBatch(
        id: (j['batchId'] ?? j['id']) as String,
        code: j['code'] as String? ?? '',
        weightKg: _num(j['weightKg']) ?? 0,
        status: j['status'] as String? ?? '',
        grade: j['currentGrade'] as String?,
        product: (j['product'] as Map?)?.cast<String, dynamic>(),
        tagUids: (j['tagUids'] as List?)?.cast<String>() ?? const [],
        unloadedAt: _date(j['unloadedAt']),
      );
}

class DriverTrip {
  const DriverTrip({
    required this.id, required this.code, required this.status, required this.plannedStart, required this.routeVersion,
    required this.stops, required this.batches, this.vehicleRegNo, this.startedAt, this.json = const {},
  });

  final String id;
  final String code;
  final String status; // ASSIGNED | PRE_CHECK_DONE | IN_PROGRESS | COMPLETED | ...
  final DateTime plannedStart;
  final DateTime? startedAt;
  final int routeVersion;
  final String? vehicleRegNo;
  final List<TripStop> stops;
  final List<TripBatch> batches;

  /// The server JSON this came from (cached for offline use).
  final Map<String, dynamic> json;

  bool get inProgress => status == 'IN_PROGRESS';
  bool get preCheckDone => status == 'PRE_CHECK_DONE';
  List<TripStop> get drops => stops.where((s) => s.isDrop).toList();
  TripStop? get nextStop => stops.where((s) => s.isOpen && s.kind != StopKind.pickup).firstOrNull;
  List<GeoPoint> get path => [for (final s in stops) s.point];

  List<TripBatch> batchesFor(TripStop stop) {
    final onBoard = batches.where((b) => b.onBoard);
    final ids = stop.expectedBatchIds;
    return ids == null ? onBoard.toList() : onBoard.where((b) => ids.contains(b.id)).toList();
  }

  factory DriverTrip.fromJson(Map<String, dynamic> j) => DriverTrip(
        id: j['id'] as String,
        code: j['code'] as String,
        status: j['status'] as String,
        plannedStart: _date(j['plannedStart']) ?? DateTime.now(),
        startedAt: _date(j['startedAt']),
        routeVersion: (j['currentRouteVersion'] as num?)?.toInt() ?? 1,
        vehicleRegNo: (j['vehicle'] as Map?)?['regNo'] as String?,
        stops: [for (final s in (j['stops'] as List? ?? const [])) TripStop.fromJson(Map<String, dynamic>.from(s as Map))]..sort((a, b) => a.seq.compareTo(b.seq)),
        batches: [for (final b in (j['batches'] as List? ?? const [])) TripBatch.fromJson(Map<String, dynamic>.from(b as Map))],
        json: j,
      );

  /// Local view after an offline change (arrive / PoD) until the server confirms.
  DriverTrip withStop(TripStop s) => DriverTrip(
        id: id, code: code, status: status, plannedStart: plannedStart, startedAt: startedAt, routeVersion: routeVersion, vehicleRegNo: vehicleRegNo,
        stops: [for (final x in stops) x.id == s.id ? s : x], batches: batches, json: json,
      );
}

/// DA-FR-05: latest pod reading and remaining shelf life per batch.
class CargoBatch {
  const CargoBatch({required this.id, required this.code, required this.product, required this.weightKg, this.grade, this.remainingH, this.safeMin, this.safeMax});
  final String id;
  final String code;
  final Map<String, dynamic> product;
  final double weightKg;
  final String? grade;
  final double? remainingH;
  final double? safeMin;
  final double? safeMax;

  factory CargoBatch.fromJson(Map<String, dynamic> j) {
    final p = Map<String, dynamic>.from(j['product'] as Map? ?? const {});
    return CargoBatch(
      id: j['batchId'] as String,
      code: j['code'] as String? ?? '',
      product: p,
      weightKg: _num(j['weightKg']) ?? 0,
      grade: j['grade'] as String?,
      remainingH: _num(j['remainingShelfLifeH']),
      safeMin: _num(p['safeTempMin']),
      safeMax: _num(p['safeTempMax']),
    );
  }
}

class CargoStatus {
  const CargoStatus({required this.batches, this.tempC, this.humidityPct, this.readingAt, this.fetchedAt, this.fromCache = false});
  final List<CargoBatch> batches;
  final double? tempC;
  final double? humidityPct;
  final DateTime? readingAt;
  final DateTime? fetchedAt;
  final bool fromCache;

  double? get lowestShelfLifeH => batches.map((b) => b.remainingH).whereType<double>().fold<double?>(null, (m, v) => m == null || v < m ? v : m);

  /// Out of the safe range of any batch on board.
  bool get tempOutOfRange => tempC != null && batches.any((b) => (b.safeMin != null && tempC! < b.safeMin!) || (b.safeMax != null && tempC! > b.safeMax!));

  factory CargoStatus.fromJson(Map<String, dynamic> j, {DateTime? fetchedAt, bool fromCache = false}) {
    final t = j['telemetry'] as Map?;
    return CargoStatus(
      batches: [for (final b in (j['batches'] as List? ?? const [])) CargoBatch.fromJson(Map<String, dynamic>.from(b as Map))],
      tempC: _num(t?['tempC']),
      humidityPct: _num(t?['humidityPct']),
      readingAt: _date(t?['ts']),
      fetchedAt: fetchedAt,
      fromCache: fromCache,
    );
  }
}

/// DA-FR-08: a proposed route next to the accepted one.
class RouteProposal {
  const RouteProposal({required this.version, required this.reason, required this.canDecline, required this.newStops, required this.oldStops, this.extraKm, this.distanceKm});
  final int version;
  final String reason; // DELAY | INCIDENT | DIVERSION | RESCUE | MANUAL
  final bool canDecline;
  final List<TripStop> newStops;
  final List<TripStop> oldStops;
  final double? extraKm;
  final double? distanceKm;

  /// The first stop that differs: what the driver drives to now.
  (TripStop?, TripStop?) get changedStop {
    final oldOpen = oldStops.where((s) => s.isOpen && s.kind != StopKind.pickup).toList();
    final newOpen = newStops.where((s) => s.isOpen && s.kind != StopKind.pickup).toList();
    for (var i = 0; i < newOpen.length; i++) {
      final o = i < oldOpen.length ? oldOpen[i] : null;
      if (o == null || o.name != newOpen[i].name || o.kind != newOpen[i].kind) return (o, newOpen[i]);
    }
    return (oldOpen.firstOrNull, newOpen.firstOrNull);
  }

  /// Null when nothing is proposed.
  static RouteProposal? fromRouteJson(Map<String, dynamic> j) {
    final p = j['pending'] as Map?;
    if (p == null) return null;
    final a = j['accepted'] as Map?;
    List<TripStop> rows(Map? plan) => [for (final s in (plan?['stopRows'] as List? ?? const [])) TripStop.fromJson(Map<String, dynamic>.from(s as Map))];
    return RouteProposal(
      version: (p['version'] as num).toInt(),
      reason: p['reason'] as String? ?? 'MANUAL',
      canDecline: p['canDecline'] == true,
      newStops: rows(p),
      oldStops: rows(a),
      extraKm: _num(p['extraKm']),
      distanceKm: _num(p['distanceKm']),
    );
  }
}

class DriverAlert {
  const DriverAlert({required this.id, required this.type, required this.severity, required this.message, required this.createdAt, this.tripId, this.status = 'OPEN'});
  final String id;
  final String type; // TEMP_EXCURSION | DRIVER_FIX | SPOILAGE_RISK | ...
  final String severity; // INFO | WARNING | CRITICAL
  final String message;
  final DateTime createdAt;
  final String? tripId;
  final String status;

  bool get critical => severity == 'CRITICAL';

  factory DriverAlert.fromJson(Map<String, dynamic> j) => DriverAlert(
        id: (j['alertId'] ?? j['id']) as String,
        type: j['type'] as String? ?? j['alertType'] as String? ?? '',
        severity: j['severity'] as String? ?? 'WARNING',
        message: j['message'] as String? ?? j['body'] as String? ?? '',
        createdAt: _date(j['createdAt']) ?? DateTime.now(),
        tripId: j['tripId'] as String?,
        status: j['status'] as String? ?? 'OPEN',
      );
}

/// One PoD row being filled in on the stop screen (DA-FR-11/12).
class PodLine {
  PodLine(this.batch);
  final TripBatch batch;
  String? scanned;
  String outcome = 'ACCEPTED'; // ACCEPTED | PARTIAL | REJECTED
  double? acceptedKg;
  String? reason;

  /// Same rules as the server (`checkOutcome`): ACCEPTED = full weight; PARTIAL 0 < kg < weight +
  /// reason; REJECTED = 0 kg + reason. Returns an error key or null.
  String? problem() {
    if (scanned == null) return 'scan';
    if (!batch.matchesScan(scanned!)) return 'tag';
    switch (outcome) {
      case 'PARTIAL':
        final kg = acceptedKg;
        if (kg == null || kg <= 0 || kg >= batch.weightKg) return 'kg';
        if ((reason ?? '').trim().isEmpty) return 'reason';
      case 'REJECTED':
        if ((reason ?? '').trim().isEmpty) return 'reason';
    }
    return null;
  }

  double get kgForServer => switch (outcome) { 'ACCEPTED' => batch.weightKg, 'REJECTED' => 0, _ => acceptedKg ?? 0 };
}

class TripHistoryItem {
  const TripHistoryItem({required this.id, required this.code, required this.status, required this.plannedStart, this.completedAt, this.distanceKm, this.podStops = 0});
  final String id;
  final String code;
  final String status;
  final DateTime plannedStart;
  final DateTime? completedAt;
  final double? distanceKm;
  final int podStops;

  factory TripHistoryItem.fromJson(Map<String, dynamic> j) => TripHistoryItem(
        id: j['id'] as String,
        code: j['code'] as String,
        status: j['status'] as String,
        plannedStart: _date(j['plannedStart']) ?? DateTime.now(),
        completedAt: _date(j['completedAt']),
        distanceKm: _num(j['distanceKm']),
        podStops: (j['podStops'] as num?)?.toInt() ?? 0,
      );
}
