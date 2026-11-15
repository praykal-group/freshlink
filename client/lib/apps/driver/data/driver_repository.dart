import 'dart:convert';

import 'package:drift/drift.dart' show BooleanExpressionOperators, OrderingTerm;
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/location/gps_fix.dart';
import '../../../core/location/gps_journal.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/database.dart';
import '../../../core/sync/outbox_repository.dart';
import 'models.dart';

const _currentKey = 'current';
String _cargoKey(String tripId) => 'driver.cargo.$tripId';
String _routeKey(String tripId) => 'driver.route.$tripId';
const _historyKey = 'driver.history';
const _ackedKey = 'driver.ackedAlerts';

/// Incident kinds of the 2-tap grid (DA-FR-09), as the server's TRIP_EVENT types.
enum IncidentKind {
  delay('INCIDENT_DELAY'),
  breakdown('INCIDENT_BREAKDOWN'),
  accident('INCIDENT_ACCIDENT'),
  roadblock('INCIDENT_ROADBLOCK'),
  reeferFault('INCIDENT_REEFER_FAULT');

  const IncidentKind(this.api);
  final String api;
}

/// Pre-check rejected by the server (422 PRE_CHECK_FAILED): what to fix.
class PreCheckFailed implements Exception {
  const PreCheckFailed(this.problems, {this.allowedMin, this.allowedMax});
  final List<String> problems; // REEFER_OFF | DOORS_OPEN | SETPOINT_OUT_OF_RANGE | INCOMPATIBLE_CARGO
  final double? allowedMin;
  final double? allowedMax;
}

/// Everything the driver app reads and writes. Writes made on the road go through the outbox
/// (DA-NFR-01): stop arrival, PoD, route acceptance, incidents, SOS, alert acks and GPS. Pre-check
/// and Start happen at the depot and need the server's answer (setpoint rules, device binding),
/// so they are online calls.
///
/// Outbox entities decide what blocks what: trip-flow ops (arrive, PoD, accept) share the trip id so
/// they apply in order; SOS, each incident, each ack and GPS have their own, so a rejected PoD can
/// never hold back an SOS.
class DriverRepository {
  DriverRepository({required this.api, required this.db, required this.outbox, Uuid? uuid, DateTime Function()? clock})
      : _uuid = uuid ?? const Uuid(),
        _now = clock ?? DateTime.now;

  final ApiClient api;
  final AppDatabase db;
  final OutboxRepository outbox;
  final Uuid _uuid;
  final DateTime Function() _now;

  // ───────────── trip (DA-FR-02) ─────────────

  /// The day's trip. Online: from the server, cached; offline: the cache. Changes still in the
  /// outbox (arrivals, PoDs, an accepted reroute) are applied on top, so the screen matches what
  /// the driver did even before the server has it.
  Future<DriverTrip?> currentTrip({bool refresh = true}) async {
    if (refresh) {
      try {
        final res = await api.get('/driver/trips/current');
        if (res == null) {
          await (db.delete(db.cachedTrips)..where((t) => t.id.equals(_currentKey))).go();
          return null;
        }
        await _cacheTrip(Map<String, dynamic>.from(res as Map));
      } on AppException catch (e) {
        if (!e.isTransient) rethrow;
      }
    }
    final cached = await (db.select(db.cachedTrips)..where((t) => t.id.equals(_currentKey))).getSingleOrNull();
    if (cached == null) {
      if (refresh) return null;
      throw const AppException(AppException.network, 'Trip not downloaded yet');
    }
    return _overlay(DriverTrip.fromJson(Map<String, dynamic>.from(jsonDecode(cached.payload) as Map)));
  }

  Future<void> _cacheTrip(Map<String, dynamic> json) => db.into(db.cachedTrips).insertOnConflictUpdate(CachedTripsCompanion.insert(id: _currentKey, payload: jsonEncode(json), updatedAt: _now().toUtc()));

  Future<DriverTrip> _overlay(DriverTrip trip) async {
    final ops = await (db.select(db.outboxOps)..where((o) => o.entityId.equals(trip.id))..orderBy([(o) => OrderingTerm(expression: o.capturedAt)])).get();
    var t = trip;
    for (final op in ops) {
      final p = Map<String, dynamic>.from(jsonDecode(op.payload) as Map);
      if (op.type == 'ROUTE_ACCEPT' && (p['version'] as num).toInt() > t.routeVersion) {
        t = await _withAcceptedRoute(t, (p['version'] as num).toInt()) ?? t;
      }
      final stop = t.stops.where((s) => s.id == p['stopId']).firstOrNull;
      if (stop == null) continue;
      if (op.type == 'STOP_ARRIVE' && stop.status == 'PENDING') t = t.withStop(stop.copyWith(status: 'ARRIVED', arrivedAt: DateTime.tryParse('${p['arrivedAt']}')?.toLocal()));
      if (op.type == 'POD') t = t.withStop(stop.copyWith(status: 'COMPLETED', completedAt: op.capturedAt.toLocal()));
    }
    return t;
  }

  /// The trip as it will be once the accepted proposal is applied (offline accept).
  Future<DriverTrip?> _withAcceptedRoute(DriverTrip t, int version) async {
    final raw = await db.kvGet(_routeKey(t.id));
    if (raw == null) return null;
    final route = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final pending = route['pending'] as Map?;
    if (pending == null || (pending['version'] as num).toInt() != version) return null;
    // a new stop for the same order expects the same batches as the old one
    final expected = {for (final s in t.stops) if (s.orderId != null) s.orderId!: s.expectedBatchIds};
    final stops = [
      for (final s in (pending['stopRows'] as List? ?? const []))
        {...Map<String, dynamic>.from(s as Map), if ((s['batchIds']) == null && expected[s['orderId']] != null) 'batchIds': expected[s['orderId']]},
    ];
    return DriverTrip.fromJson({...t.json, 'currentRouteVersion': version, 'stops': stops});
  }

  Future<List<TripHistoryItem>> history() async {
    try {
      final res = Map<String, dynamic>.from(await api.get('/driver/trips', query: {'limit': 30}) as Map);
      await db.kvSet(_historyKey, jsonEncode(res['items']));
      return [for (final i in res['items'] as List) TripHistoryItem.fromJson(Map<String, dynamic>.from(i as Map))];
    } on AppException catch (e) {
      final cached = await db.kvGet(_historyKey);
      if (!e.isTransient || cached == null) rethrow;
      return [for (final i in jsonDecode(cached) as List) TripHistoryItem.fromJson(Map<String, dynamic>.from(i as Map))];
    }
  }

  // ───────────── cargo (DA-FR-05) and route (DA-FR-08) ─────────────

  Future<CargoStatus> cargo(String tripId) async {
    try {
      final json = Map<String, dynamic>.from(await api.get('/trips/$tripId/cargo-status') as Map);
      await db.kvSet(_cargoKey(tripId), jsonEncode({...json, '_at': _now().toUtc().toIso8601String()}));
      return CargoStatus.fromJson(json, fetchedAt: _now());
    } on AppException catch (e) {
      final raw = await db.kvGet(_cargoKey(tripId));
      if (!e.isTransient || raw == null) rethrow;
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return CargoStatus.fromJson(json, fetchedAt: DateTime.tryParse('${json['_at']}')?.toLocal(), fromCache: true);
    }
  }

  /// A pending reroute, or null. Cached so it can be accepted offline.
  Future<RouteProposal?> proposal(String tripId) async {
    Map<String, dynamic> json;
    try {
      json = Map<String, dynamic>.from(await api.get('/trips/$tripId/route') as Map);
      await db.kvSet(_routeKey(tripId), jsonEncode(json));
    } on AppException catch (e) {
      final raw = await db.kvGet(_routeKey(tripId));
      if (!e.isTransient || raw == null) rethrow;
      json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    }
    final p = RouteProposal.fromRouteJson(json);
    if (p == null) return null;
    final accepted = await (db.select(db.outboxOps)..where((o) => o.type.equals('ROUTE_ACCEPT') & o.entityId.equals(tripId))).get();
    final done = accepted.any((o) => ((jsonDecode(o.payload) as Map)['version'] as num).toInt() >= p.version);
    return done ? null : p;
  }

  /// DA-FR-08: queued (the driver may be offline); the trip view switches at once.
  Future<void> acceptRoute(String tripId, int version) => outbox.enqueue(type: 'ROUTE_ACCEPT', entityId: tripId, payload: {'tripId': tripId, 'version': version}, capturedAt: _now());

  /// Only non-critical replans can be declined (the server refuses the others), so this is online.
  Future<void> declineRoute(String tripId, int version) => api.post('/trips/$tripId/routes/$version/decline');

  // ───────────── depot: pre-check + start (DA-FR-03) ─────────────

  /// Remote config `gpsIntervalSec` (Section 10.5, 5..600 s) from the masters bundle; the last
  /// known value offline; the seed default 30 s before the first download.
  Future<int> gpsIntervalSec() async {
    try {
      final bundle = Map<String, dynamic>.from(await api.get('/masters/bundle') as Map);
      final v = ((bundle['config'] as Map?)?['gpsIntervalSec'] as num?)?.toInt();
      if (v != null && v >= 5 && v <= 600) {
        await db.kvSet('driver.gpsIntervalSec', '$v');
        return v;
      }
    } on AppException catch (e) {
      if (!e.isTransient) rethrow;
    }
    return int.tryParse(await db.kvGet('driver.gpsIntervalSec') ?? '') ?? 30;
  }

  Future<void> preCheck(String tripId, {required bool reeferOn, required double setpointC, required bool doorsClosed}) async {
    try {
      await api.post('/trips/$tripId/pre-check', body: {'id': _uuid.v4(), 'reeferOn': reeferOn, 'setpointC': setpointC, 'doorsClosed': doorsClosed, 'occurredAt': _now().toUtc().toIso8601String()});
    } on AppException catch (e) {
      if (e.code != 'PRE_CHECK_FAILED') rethrow;
      final d = e.details;
      final allowed = d['allowed'] as Map?;
      throw PreCheckFailed(((d['problems'] as List?) ?? const []).cast<String>(), allowedMin: (allowed?['min'] as num?)?.toDouble(), allowedMax: (allowed?['max'] as num?)?.toDouble());
    }
  }

  Future<void> start(String tripId) => api.post('/trips/$tripId/start');

  // ───────────── on the road (outbox) ─────────────

  /// DA-FR-14: SOS with the last position. Its own entity: nothing can block it.
  Future<void> sos(String tripId, {GpsFix? at}) {
    final id = _uuid.v4();
    return outbox.enqueue(
      type: 'TRIP_EVENT',
      entityId: 'sos:$id',
      payload: {'tripId': tripId, 'id': id, 'type': 'SOS', 'occurredAt': _now().toUtc().toIso8601String(), if (at != null) 'lat': at.lat, if (at != null) 'lng': at.lng},
      capturedAt: _now(),
    );
  }

  /// DA-FR-09: two taps + optional photo / voice note (≤ 60 s); the server replans.
  Future<void> reportIncident(String tripId, IncidentKind kind, {GpsFix? at, ({String path, int bytes})? photo, ({String path, int bytes, int seconds})? voice}) async {
    final id = _uuid.v4();
    final files = <String>[];
    Map<String, String>? photoRef, voiceRef;
    if (photo != null) {
      final f = await outbox.addFile(localPath: photo.path, purpose: 'INCIDENT_PHOTO', contentType: 'image/jpeg', sizeBytes: photo.bytes);
      files.add(f);
      photoRef = OutboxRepository.fileRef(f);
    }
    if (voice != null) {
      final f = await outbox.addFile(localPath: voice.path, purpose: 'VOICE_NOTE', contentType: 'audio/mp4', sizeBytes: voice.bytes);
      files.add(f);
      voiceRef = OutboxRepository.fileRef(f);
    }
    await outbox.enqueue(
      type: 'TRIP_EVENT',
      entityId: 'event:$id',
      fileIds: files,
      capturedAt: _now(),
      payload: {
        'tripId': tripId,
        'id': id,
        'type': kind.api,
        'occurredAt': _now().toUtc().toIso8601String(),
        if (at != null) 'lat': at.lat,
        if (at != null) 'lng': at.lng,
        'photoKey': ?photoRef,
        'voiceKey': ?voiceRef,
        if (voice != null) 'payload': {'voiceSeconds': voice.seconds},
      },
    );
  }

  /// DA-FR-07: acknowledged on the phone at once; the server gets it when online.
  Future<void> ackAlert(String alertId) async {
    await outbox.enqueue(type: 'ALERT_ACK', entityId: 'alert:$alertId', payload: {'alertId': alertId}, capturedAt: _now());
    final acked = await ackedAlerts();
    await db.kvSet(_ackedKey, jsonEncode({...acked, alertId}.toList()));
  }

  Future<Set<String>> ackedAlerts() async {
    final raw = await db.kvGet(_ackedKey);
    return raw == null ? {} : (jsonDecode(raw) as List).cast<String>().toSet();
  }

  /// Open alerts of the trip not yet acknowledged here (also catches alerts missed while offline).
  Future<List<DriverAlert>> openAlerts(String tripId) async {
    final res = Map<String, dynamic>.from(await api.get('/alerts', query: {'tripId': tripId, 'status': 'OPEN', 'limit': 20}) as Map);
    final acked = await ackedAlerts();
    return [
      for (final a in res['items'] as List)
        if (!acked.contains((a as Map)['id'])) DriverAlert.fromJson(Map<String, dynamic>.from(a)),
    ];
  }

  /// DA-FR-10: journalled fixes → GPS_POINTS ops (≤ 500 points each, the server limit).
  Future<int> drainGps(String tripId, GpsJournal journal) => journal.drain((fixes) async {
        for (var i = 0; i < fixes.length; i += 500) {
          final chunk = fixes.sublist(i, (i + 500).clamp(0, fixes.length));
          await outbox.enqueue(type: 'GPS_POINTS', entityId: 'gps:$tripId', capturedAt: chunk.first.at, payload: {'tripId': tripId, 'points': [for (final f in chunk) f.toJson()]});
        }
      });

  // ───────────── stop + PoD (DA-FR-11/12) ─────────────

  Future<void> arrive(String tripId, TripStop stop, {GpsFix? at}) => outbox.enqueue(
        type: 'STOP_ARRIVE',
        entityId: tripId,
        capturedAt: _now(),
        payload: {'tripId': tripId, 'stopId': stop.id, 'arrivedAt': _now().toUtc().toIso8601String(), if (at != null) 'lat': at.lat, if (at != null) 'lng': at.lng},
      );

  /// One submission per stop. Every line must be valid first ([PodLine.problem]).
  Future<void> submitPod(
    String tripId,
    TripStop stop, {
    required List<PodLine> lines,
    required String receiverName,
    required ({String path, int bytes}) signature,
    required ({String path, int bytes}) photo,
    required GpsFix at,
  }) async {
    final bad = lines.where((l) => l.problem() != null);
    if (bad.isNotEmpty) throw ArgumentError('PoD line ${bad.first.batch.code}: ${bad.first.problem()}');
    final sig = await outbox.addFile(localPath: signature.path, purpose: 'POD_SIGNATURE', contentType: 'image/png', sizeBytes: signature.bytes);
    final pic = await outbox.addFile(localPath: photo.path, purpose: 'POD_PHOTO', contentType: 'image/jpeg', sizeBytes: photo.bytes);
    await outbox.enqueue(
      type: 'POD',
      entityId: tripId,
      fileIds: [sig, pic],
      capturedAt: _now(),
      payload: {
        'tripId': tripId,
        'stopId': stop.id,
        'receiverName': receiverName.trim(),
        'signatureKey': OutboxRepository.fileRef(sig),
        'photoKey': OutboxRepository.fileRef(pic),
        'capturedAt': _now().toUtc().toIso8601String(),
        'lat': at.lat,
        'lng': at.lng,
        'items': [
          for (final l in lines)
            {
              'id': _uuid.v4(),
              'batchId': l.batch.id,
              'outcome': l.outcome,
              'acceptedKg': l.kgForServer,
              if (l.outcome != 'ACCEPTED') 'reason': l.reason!.trim(),
              'scannedTagUid': l.scanned,
            },
        ],
      },
    );
  }

  /// Uploads and ops of this trip still on the phone (DA-FR-13 "pending uploads").
  Future<int> pendingFor(String tripId) async {
    final ops = await db.select(db.outboxOps).get();
    return ops.where((o) => o.entityId == tripId || o.entityId == 'gps:$tripId' || (jsonDecode(o.payload) as Map)['tripId'] == tripId).length;
  }
}
