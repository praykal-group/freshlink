import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/alarm/alert_alarm.dart';
import '../../core/config/env.dart';
import '../../core/location/gps_fix.dart';
import '../../core/location/gps_journal.dart';
import '../../core/location/speed_lock.dart';
import '../../core/location/trip_tracker.dart';
import '../../core/map/caching_tile_provider.dart';
import '../../core/providers.dart';
import 'data/driver_repository.dart';
import 'data/models.dart';

final driverRepositoryProvider = Provider<DriverRepository>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) throw StateError('the driver app needs the local database');
  return DriverRepository(api: ref.watch(apiClientProvider), db: db, outbox: ref.watch(outboxProvider)!);
});

/// The day's trip (DA-FR-02). [refresh] reloads from the server; [reload] re-reads the local
/// copy after an offline change (arrive, PoD, accept).
class CurrentTripController extends AsyncNotifier<DriverTrip?> {
  @override
  Future<DriverTrip?> build() {
    final trip = ref.watch(driverRepositoryProvider).currentTrip();
    trip.then((t) {
      if (t != null) ref.read(realtimeProvider)?.joinTrip(t.id); // alert.raised / route.proposed go to the trip room
    }, onError: (_) {});
    return trip;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(driverRepositoryProvider).currentTrip());
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(() => ref.read(driverRepositoryProvider).currentTrip(refresh: false));
  }
}

final currentTripProvider = AsyncNotifierProvider<CurrentTripController, DriverTrip?>(CurrentTripController.new);

/// DA-FR-05: cargo refreshed every 60 s (and on `cargo.status`).
final cargoProvider = StreamProvider.autoDispose.family<CargoStatus, String>((ref, tripId) {
  final repo = ref.watch(driverRepositoryProvider);
  final out = StreamController<CargoStatus>();
  Future<void> load() async {
    try {
      out.add(await repo.cargo(tripId));
    } catch (e, s) {
      out.addError(e, s);
    }
  }

  unawaited(load());
  final timer = Timer.periodic(const Duration(seconds: 60), (_) => load());
  final sub = ref.watch(realtimeProvider)?.stream.where((e) => e.name == 'cargo.status' && e.data['tripId'] == tripId).listen((_) => load());
  ref.onDispose(() {
    timer.cancel();
    sub?.cancel();
    out.close();
  });
  return out.stream;
});

/// GPS tracking (DA-FR-10). Null where there is no foreground service (web, widget tests).
final tripTrackerProvider = FutureProvider<TripTracker?>((ref) async => ForegroundTripTracker(GpsJournal(await gpsJournalDir())));

/// Latest phone fix (truck marker, SOS position, PoD location).
class LastFixController extends Notifier<GpsFix?> {
  @override
  GpsFix? build() {
    final tracker = ref.watch(tripTrackerProvider).value;
    final sub = tracker?.fixes.listen((f) => state = f);
    ref.onDispose(() => sub?.cancel());
    return null;
  }

  void set(GpsFix f) => state = f;
}

final lastFixProvider = NotifierProvider<LastFixController, GpsFix?>(LastFixController.new);

/// DA-NFR-08 speed lock, fed by every fix.
class SpeedLockController extends Notifier<bool> {
  final _lock = SpeedLock();

  @override
  bool build() {
    ref.listen<GpsFix?>(lastFixProvider, (_, f) {
      if (f != null) state = _lock.update(f);
    });
    return false;
  }

  void reset() {
    _lock.reset();
    state = false;
  }
}

final speedLockProvider = NotifierProvider<SpeedLockController, bool>(SpeedLockController.new);

/// Moves journalled GPS fixes into the outbox every minute and before each sync pass.
final gpsDrainWorkerProvider = Provider.autoDispose<void>((ref) {
  final trip = ref.watch(currentTripProvider).value;
  final tracker = ref.watch(tripTrackerProvider).value;
  if (trip == null || !trip.inProgress || tracker == null) return;
  final repo = ref.read(driverRepositoryProvider);
  Future<void> drain() => repo.drainGps(trip.id, tracker.journal).catchError((_) => 0);
  final timer = Timer.periodic(const Duration(seconds: 60), (_) => drain());
  unawaited(drain());
  ref.onDispose(timer.cancel);
});

/// Sound + voice for critical alerts (DA-FR-06).
final alertAlarmProvider = Provider<AlertAlarm>((ref) {
  final alarm = AlertAlarm(DeviceAlarmOutput());
  ref.onDispose(alarm.stop);
  return alarm;
});

/// What needs the driver now: an unacknowledged alert and/or a route proposal. Fed by realtime +
/// push (`alert.raised`, `route.proposed`, < 10 s, DA-NFR) and a 60 s poll that also catches
/// what arrived while the phone was offline.
class DriverAttention {
  const DriverAttention({this.alerts = const [], this.proposal});
  final List<DriverAlert> alerts;
  final RouteProposal? proposal;

  DriverAlert? get topAlert => alerts.isEmpty ? null : (alerts.where((a) => a.critical).firstOrNull ?? alerts.first);
}

class AttentionController extends Notifier<DriverAttention> {
  Timer? _poll;

  @override
  DriverAttention build() {
    final trip = ref.watch(currentTripProvider).value;
    _poll?.cancel();
    if (trip == null || !trip.inProgress) return const DriverAttention();
    final sub = ref.watch(realtimeProvider)?.stream.listen((e) {
      if (e.data['tripId'] != null && e.data['tripId'] != trip.id) return;
      if (e.name == 'alert.raised') {
        final a = DriverAlert.fromJson(e.data);
        if (!state.alerts.any((x) => x.id == a.id)) state = DriverAttention(alerts: [a, ...state.alerts], proposal: state.proposal);
      } else if (e.name == 'alert.updated' && e.data['status'] != 'OPEN') {
        dismissAlert('${e.data['alertId'] ?? e.data['id']}');
      } else if (e.name == 'route.proposed' || e.name == 'route.updated' || e.name == 'trip.updated') {
        unawaited(refresh());
      }
    });
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
    ref.onDispose(() {
      _poll?.cancel();
      sub?.cancel();
    });
    unawaited(Future.microtask(refresh));
    return const DriverAttention();
  }

  Future<void> refresh() async {
    final trip = ref.read(currentTripProvider).value;
    if (trip == null) return;
    final repo = ref.read(driverRepositoryProvider);
    List<DriverAlert>? alerts;
    RouteProposal? proposal = state.proposal;
    try {
      alerts = await repo.openAlerts(trip.id);
    } catch (_) {/* offline: keep what we have */}
    try {
      proposal = await repo.proposal(trip.id);
    } catch (_) {}
    if (!ref.mounted) return;
    state = DriverAttention(alerts: alerts ?? state.alerts, proposal: proposal);
  }

  void dismissAlert(String id) {
    state = DriverAttention(alerts: state.alerts.where((a) => a.id != id).toList(), proposal: state.proposal);
    if (ref.read(alertAlarmProvider).activeAlertId == id) unawaited(ref.read(alertAlarmProvider).stop());
  }

  void proposalHandled() => state = DriverAttention(alerts: state.alerts);
}

// autoDispose: polling stops when no trip screen is open (it restarts with a fresh refresh).
final attentionProvider = NotifierProvider.autoDispose<AttentionController, DriverAttention>(AttentionController.new);

/// Map tiles through the disk cache (DA-NFR-01). Null when no storage is available.
final tileProviderProvider = FutureProvider<CachingTileProvider?>((ref) async {
  final gps = await gpsJournalDir(); // <support>/gps → <support>/tiles beside it
  return CachingTileProvider(store: TileStore(Directory('${gps.parent.path}/tiles')), fetch: dioTileFetch('in.iccms.driver'), urlTemplate: Env.mapTileUrl);
});
