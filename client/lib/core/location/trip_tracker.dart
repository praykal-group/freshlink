import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import 'gps_fix.dart';
import 'gps_journal.dart';

/// Why tracking could not start (shown to the driver with a fix-it button).
enum TrackingProblem { locationOff, permissionDenied, permissionDeniedForever, notificationsDenied, failed }

/// Phone GPS while a trip is active (DA-FR-10, Section 10.5 foreground service). The app talks to
/// this interface; tests use a fake that emits fixes.
abstract class TripTracker {
  /// Every fix while tracking (speed lock, truck marker). Journalled fixes reach the outbox via [journal].
  Stream<GpsFix> get fixes;
  GpsJournal get journal;
  Future<bool> get isRunning;

  /// Returns null when tracking runs, else what stops it.
  Future<TrackingProblem?> start({required String tripCode, required String title, required String text, required int gpsIntervalSec});
  Future<void> stop();
}

const _kIntervalKey = 'gpsIntervalSec';
const _kJournalKey = 'journalDir';

/// How often the service asks for a fix. The speed lock needs a fresh speed (DA-NFR-08), while
/// only one fix per `gpsIntervalSec` is journalled for upload (D-142).
const kSpeedSampleInterval = Duration(seconds: 10);

Future<Directory> gpsJournalDir() async => Directory('${(await getApplicationSupportDirectory()).path}/gps');

/// Entry point of the foreground-service isolate (flutter_foreground_task starts its own engine,
/// so tracking survives the driver closing the app).
@pragma('vm:entry-point')
void gpsTaskCallback() => FlutterForegroundTask.setTaskHandler(GpsTaskHandler());

/// Runs in the service isolate: a position stream; each fix goes to the app (if it is alive), and
/// one per interval is appended to the journal (which survives the app being closed).
class GpsTaskHandler extends TaskHandler {
  StreamSubscription<Position>? _sub;
  GpsJournal? _journal;
  DateTime? _lastJournalled;
  Duration _interval = const Duration(seconds: 30);

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _interval = Duration(seconds: (await FlutterForegroundTask.getData<int>(key: _kIntervalKey)) ?? 30);
    final dir = await FlutterForegroundTask.getData<String>(key: _kJournalKey);
    _journal = GpsJournal(dir != null ? Directory(dir) : await gpsJournalDir());
    _sub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(accuracy: LocationAccuracy.high, distanceFilter: 0, intervalDuration: kSpeedSampleInterval),
    ).listen(_onPosition, onError: (_) {/* GPS off mid-trip: the app shows it from its own check */});
  }

  Future<void> _onPosition(Position p) async {
    final fix = GpsFix(at: p.timestamp.toUtc(), lat: p.latitude, lng: p.longitude, speedKmh: GpsFix.kmhFromMps(p.speed), accuracyM: p.accuracy);
    FlutterForegroundTask.sendDataToMain(fix.toJson());
    final last = _lastJournalled;
    if (last == null || fix.at.difference(last) >= _interval - const Duration(seconds: 1)) {
      _lastJournalled = fix.at;
      await _journal?.append(fix);
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _sub?.cancel();
  }
}

class ForegroundTripTracker implements TripTracker {
  ForegroundTripTracker(this.journal) {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onData);
  }

  @override
  final GpsJournal journal;
  final _fixes = StreamController<GpsFix>.broadcast();

  @override
  Stream<GpsFix> get fixes => _fixes.stream;

  void _onData(Object data) {
    final f = GpsFix.tryParse(data);
    if (f != null) _fixes.add(f);
  }

  @override
  Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  @override
  Future<TrackingProblem?> start({required String tripCode, required String title, required String text, required int gpsIntervalSec}) async {
    if (!await Geolocator.isLocationServiceEnabled()) return TrackingProblem.locationOff;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever) return TrackingProblem.permissionDeniedForever;
    if (perm == LocationPermission.denied || perm == LocationPermission.unableToDetermine) return TrackingProblem.permissionDenied;
    // Android 13+: the "Trip in progress" notification needs permission; the service would still run
    // without it, but the driver could not see that tracking is on.
    if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
      if (await FlutterForegroundTask.requestNotificationPermission() != NotificationPermission.granted) return TrackingProblem.notificationsDenied;
    }
    if (await isRunning) return null;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'iccms_trip',
        channelName: 'Trip in progress',
        channelDescription: 'Shown while the trip is tracked',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(eventAction: ForegroundTaskEventAction.nothing(), allowWakeLock: true, allowAutoRestart: true, stopWithTask: false),
    );
    await FlutterForegroundTask.saveData(key: _kIntervalKey, value: gpsIntervalSec);
    await FlutterForegroundTask.saveData(key: _kJournalKey, value: journal.dir.path);
    final r = await FlutterForegroundTask.startService(
      serviceId: 412,
      serviceTypes: [ForegroundServiceTypes.location],
      notificationTitle: title,
      notificationText: text,
      callback: gpsTaskCallback,
    );
    return r is ServiceRequestSuccess ? null : TrackingProblem.failed;
  }

  @override
  Future<void> stop() async {
    if (await isRunning) await FlutterForegroundTask.stopService();
  }
}
