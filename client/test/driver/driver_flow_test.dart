import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:iccms/apps/driver/providers.dart';
import 'package:iccms/apps/driver/router.dart';
import 'package:iccms/apps/driver/screens/stop_screen.dart';
import 'package:iccms/apps/driver/widgets/driver_widgets.dart';
import 'package:iccms/bootstrap.dart';
import 'package:iccms/core/alarm/alert_alarm.dart';
import 'package:iccms/core/config/app_flavor.dart';
import 'package:iccms/core/location/gps_fix.dart';
import 'package:iccms/core/location/gps_journal.dart';
import 'package:iccms/core/location/trip_tracker.dart';
import 'package:iccms/core/providers.dart';
import 'package:iccms/core/realtime/realtime_client.dart';
import 'package:iccms/core/router/app_router.dart';
import 'package:iccms/core/storage/database.dart';
import 'package:iccms/core/sync/api_sync_api.dart';
import 'package:iccms/core/sync/sync_engine.dart';
import 'package:iccms/core/sync/sync_scheduler.dart';
import 'package:iccms/core/tags/tag_reader.dart';
import 'package:iccms/shared/screens/camera_screen.dart';
import 'package:iccms/shared/widgets/tag_picker.dart';

import '../helpers.dart';
import 'fake_driver_server.dart';

/// Uploads from memory (the widget-test clock does not run real file IO).
class _MemSyncApi extends ApiSyncApi {
  _MemSyncApi(super.api);
  @override
  Future<void> upload(Presigned target, String localPath) => api.putToPresignedUrl(target.uploadUrl, Stream.value(const [1, 2, 3]), target.headers);
}

class _MemJournal extends GpsJournal {
  _MemJournal() : super(Directory('unused'));
  final fixes = <GpsFix>[];
  @override
  Future<void> append(GpsFix fix) async => fixes.add(fix);
  @override
  Future<int> drain(Future<void> Function(List<GpsFix> fixes) consume) async {
    if (fixes.isEmpty) return 0;
    final taken = [...fixes];
    fixes.clear();
    await consume(taken);
    return taken.length;
  }
}

/// Stands in for the foreground service: [emit] is a GPS fix (sent to the app and journalled).
class _FakeTracker implements TripTracker {
  final _c = StreamController<GpsFix>.broadcast();
  @override
  final _MemJournal journal = _MemJournal();
  bool running = false;
  @override
  Stream<GpsFix> get fixes => _c.stream;
  @override
  Future<bool> get isRunning async => running;
  @override
  Future<TrackingProblem?> start({required String tripCode, required String title, required String text, required int gpsIntervalSec}) async {
    running = true;
    return null;
  }

  @override
  Future<void> stop() async => running = false;

  void emit(GpsFix f) {
    _c.add(f);
    unawaited(journal.append(f));
  }
}

class _RecAlarm implements AlarmOutput {
  final log = <String>[];
  @override
  Future<void> startLoop(String title, String body) async => log.add('loop:$title');
  @override
  Future<void> stopLoop() async => log.add('stopLoop');
  @override
  Future<void> ring(String title, String body) async => log.add('ring');
  @override
  Future<void> speak(String text, String languageTag) async => log.add('speak:$languageTag');
  @override
  Future<void> stopSpeaking() async => log.add('stopSpeaking');
}

class _Reader implements TagReader {
  const _Reader(this.kind, this.uid);
  @override
  final TagKind kind;
  final String uid;
  @override
  Future<TagRead?> read(BuildContext context) async => TagRead(kind, uid);
}

GpsFix _fix(int s, double kmh) => GpsFix(at: DateTime.now().toUtc().add(Duration(seconds: s)), lat: 19.70, lng: 75.36, speedKmh: kmh, accuracyM: 8);

/// Section 16 / M12: the driver screens, outbox, sync engine and API client against a scripted
/// backend: a simulated trip with an offline delivery, an alert, a reroute and the speed lock.
void main() {
  late FakeDriverServer server;
  late AppDatabase db;
  late ProviderContainer c;
  late _FakeTracker tracker;
  late _RecAlarm alarm;
  late RealtimeClient realtime;
  late List<(double, double, String)> navigations;
  var disposed = false;

  Future<void> run(WidgetTester t, [int ticks = 10]) async {
    for (var i = 0; i < ticks; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<T> drive<T>(WidgetTester t, Future<T> f) async {
    T? value;
    Object? error;
    var done = false;
    f.then((v) {
      value = v;
      done = true;
    }, onError: (Object e) {
      error = e;
      done = true;
    });
    for (var i = 0; i < 300 && !done; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    if (error != null) throw error!;
    if (!done) throw StateError('future did not complete');
    return value as T;
  }

  Future<void> boot(WidgetTester t, {String status = 'ASSIGNED'}) async {
    t.view.physicalSize = const Size(1080, 5400); // 360×1800 dp: the whole PoD form is built
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    server = FakeDriverServer()..status = status;
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close); // outside the fake clock (closing inside it never completes)
    tracker = _FakeTracker();
    alarm = _RecAlarm();
    navigations = [];
    disposed = false;
    realtime = RealtimeClient(url: 'ws://unused', flavor: 'driver', token: () => null); // not connected: events are injected
    c = ProviderContainer(overrides: [
      ...overridesFor(AppFlavor.driver, backend: FakeAuthBackend()..session = true, adapter: server.adapter, router: const DriverRouter()).cast<Override>(),
      databaseProvider.overrideWithValue(db),
      syncSchedulerProvider.overrideWith((ref) => SyncScheduler(SyncEngine(ref.watch(databaseProvider)!, _MemSyncApi(ref.watch(apiClientProvider))))),
      realtimeProvider.overrideWithValue(realtime),
      tripTrackerProvider.overrideWith((ref) async => tracker),
      tileProviderProvider.overrideWith((ref) async => null),
      alertAlarmProvider.overrideWithValue(AlertAlarm(alarm)),
      navigateProvider.overrideWithValue((lat, lng, label) async {
        navigations.add((lat, lng, label));
        return true;
      }),
      tagReadersProvider.overrideWithValue(const {
        TagKind.nfc: _Reader(TagKind.nfc, '04A1B2C3D4E5F6'), // batch 1's tag
        TagKind.qr: _Reader(TagKind.qr, 'FSH-20261115-DCK-PTN-0002'), // batch 2's label QR
        TagKind.uhf: _Reader(TagKind.uhf, 'E200999999'), // not on this truck
      }),
      photoCaptureProvider.overrideWithValue((context, {required title, required instruction, required fileStem}) async =>
          CapturedPhoto(path: 'missing/$fileStem.jpg', originalPath: 'missing/$fileStem.jpg', sizeBytes: 310 * 1024, width: 1280, height: 960, capturedAt: DateTime.now())),
      signatureSaverProvider.overrideWithValue((_) async => (path: 'missing/sig.png', bytes: 9000)),
    ]);
    await t.pumpWidget(UncontrolledProviderScope(container: c, child: const IccmsApp()));
    await run(t, 20);
  }

  /// Tears down while the test clock still runs (periodic cargo / alert polls are cancelled).
  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    if (!disposed) {
      disposed = true;
      c.dispose();
    }
    await t.pump(const Duration(milliseconds: 100));
  }

  Future<void> openTrip(WidgetTester t) async {
    unawaited(c.read(routerProvider).push('/trip'));
    await run(t, 15);
  }

  testWidgets('a full trip: pre-check → start → navigate → offline delivery → reconnect: synced exactly once, in order', (t) async {
    await boot(t);
    expect(find.text('TRP-20261115-0001'), findsOneWidget);
    expect(t.widget<FilledButton>(find.descendant(of: find.byKey(const Key('start-trip')), matching: find.byType(FilledButton))).onPressed, isNull, reason: 'Start needs the pre-check (DA-FR-03)');

    // pre-check: a wrong setpoint is refused with the allowed range, then passes
    await t.tap(find.byKey(const Key('pre-check')));
    await run(t);
    for (final k in ['pc-reefer', 'pc-setpoint-ok', 'pc-doors']) {
      await t.tap(find.byKey(Key(k)));
      await t.pump();
    }
    await t.enterText(find.byKey(const Key('pc-setpoint')), '8');
    await t.tap(find.byKey(const Key('pc-submit')));
    await run(t);
    expect(find.byKey(const Key('pc-failed')), findsOneWidget);
    expect(find.textContaining('0.0 to 4.0'), findsOneWidget);
    await t.enterText(find.byKey(const Key('pc-setpoint')), '2');
    await t.tap(find.byKey(const Key('pc-submit')));
    await run(t, 15);
    expect(server.status, 'PRE_CHECK_DONE');

    // start: tracking first, then the server binds the phone
    await t.tap(find.byKey(const Key('start-trip')));
    await run(t, 20);
    expect(tracker.running, isTrue);
    expect(server.status, 'IN_PROGRESS');
    expect(find.byKey(const Key('next-stop')), findsOneWidget);
    expect(find.text('Sambhajinagar DC'), findsWidgets);
    expect(find.byKey(const Key('cargo-temp')), findsOneWidget, reason: 'cargo strip (DA-FR-05)');

    await t.tap(find.byKey(const Key('navigate')).first);
    await t.pump();
    expect(navigations.single, (19.8762, 75.3433, 'Sambhajinagar DC'), reason: 'Google Maps hand-off to the next stop');

    // GPS on the road (DA-FR-10), then the network drops before the drop point
    tracker.emit(_fix(0, 5));
    tracker.emit(_fix(30, 6));
    await run(t, 3);
    server.online = false;

    await t.tap(find.byKey(const Key('open-stop')));
    await run(t);
    await t.tap(find.byKey(const Key('arrive')));
    await run(t, 15);
    expect(find.byKey(const Key('pod-progress')), findsOneWidget, reason: 'arrival applied locally while offline');

    // scans: a crate that is not on this truck is refused; the two right crates are taken
    await t.tap(find.byKey(const Key('tag-uhf')));
    await run(t, 3);
    expect(find.byKey(const Key('pod-scan-warning')), findsOneWidget);
    await t.tap(find.byKey(const Key('tag-nfc')));
    await run(t, 3);
    await t.tap(find.byKey(const Key('tag-qr')));
    await run(t, 3);
    expect(find.text('Scan each crate: 2 of 2'), findsOneWidget);

    // batch 2: partial, 60 of 80 kg
    await t.tap(find.descendant(of: find.byKey(const Key('pod-outcome-FSH-20261115-DCK-PTN-0002')), matching: find.text('Partial')));
    await t.pump();
    await t.tap(find.byKey(const Key('pod-submit')));
    await run(t, 3);
    expect(find.byKey(const Key('pod-problems')), findsOneWidget, reason: 'kg, reason, receiver, signature and photo are missing');
    await t.enterText(find.byKey(const Key('pod-kg-FSH-20261115-DCK-PTN-0002')), '60');
    await t.enterText(find.byKey(const Key('pod-reason-FSH-20261115-DCK-PTN-0002')), 'two crates crushed');
    await t.enterText(find.byKey(const Key('pod-receiver')), 'Anil Patil');
    await t.drag(find.byKey(const Key('pod-signature')), const Offset(120, 30));
    await t.pump();
    await t.tap(find.byKey(const Key('pod-photo')));
    await run(t, 3);
    await t.tap(find.byKey(const Key('pod-submit')));
    await run(t, 20);
    expect(find.byKey(const Key('all-done')), findsOneWidget, reason: 'the stop is done on the phone before the server knows');
    await t.pump(const Duration(seconds: 61)); // the GPS worker drains the journal (every minute and on trip reload)
    await run(t, 5);
    expect(tracker.journal.fixes, isEmpty, reason: 'journal drained into the outbox');
    expect((await drive(t, db.select(db.outboxOps).get())).map((o) => o.type).toSet(), {'STOP_ARRIVE', 'POD', 'GPS_POINTS'});
    expect(server.appliedTypes, isEmpty);

    // back online: one forced pass
    server.online = true;
    await drive(t, c.read(syncSchedulerProvider)!.syncNow());
    await run(t, 5);
    expect(server.appliedTypes.where((x) => x != 'GPS_POINTS'), ['STOP_ARRIVE', 'POD'], reason: 'arrival before the PoD of the same stop');
    expect(server.appliedTypes.where((x) => x == 'GPS_POINTS').length, 1);
    expect(server.uploads.length, 2, reason: 'signature + photo uploaded before the PoD');
    final pod = server.applied.values.firstWhere((o) => o['type'] == 'POD')['payload'] as Map;
    expect(pod['receiverName'], 'Anil Patil');
    expect([for (final i in pod['items'] as List) [i['outcome'], i['acceptedKg'], i['scannedTagUid']]], [
      ['ACCEPTED', 120.0, '04A1B2C3D4E5F6'],
      ['PARTIAL', 60.0, 'FSH-20261115-DCK-PTN-0002'],
    ]);
    expect(pod['signatureKey'], startsWith('POD/'), reason: 'the file placeholder was replaced by the S3 key');
    final gps = server.applied.values.firstWhere((o) => o['type'] == 'GPS_POINTS')['payload'] as Map;
    expect((gps['points'] as List).length, 2);
    expect(await drive(t, db.select(db.outboxOps).get()), isEmpty);
    final applied = server.applied.length;
    await drive(t, c.read(syncSchedulerProvider)!.syncNow());
    expect(server.applied.length, applied, reason: 'nothing sent twice');
    await finish(t);
  });

  testWidgets('critical alert: full screen with alarm + voice within seconds; Acknowledge stops it and reaches the server', (t) async {
    await boot(t, status: 'IN_PROGRESS');
    await openTrip(t);
    expect(alarm.log, isEmpty);

    server.alerts.add({'id': 'al-1', 'type': 'TEMP_EXCURSION', 'severity': 'CRITICAL', 'message': 'Reefer at 9.1 °C', 'status': 'OPEN', 'tripId': FakeDriverServer.tripId, 'createdAt': '2026-11-15T04:00:00Z'});
    realtime.inject(const RealtimeEvent('alert.raised', {'alertId': 'al-1', 'type': 'TEMP_EXCURSION', 'severity': 'CRITICAL', 'tripId': FakeDriverServer.tripId, 'message': 'Reefer at 9.1 °C'}));
    await run(t, 10); // 1 s, far under the 60 s poll: it came through the event
    expect(find.byKey(const Key('alert-title')), findsOneWidget);
    expect(find.text('Temperature out of range'), findsOneWidget);
    expect(alarm.log.take(2), ['loop:Temperature out of range', 'speak:en-IN']);

    await t.tap(find.byKey(const Key('ack')));
    await run(t, 20);
    expect(alarm.log, containsAll(['stopLoop', 'stopSpeaking']));
    expect(find.byKey(const Key('alert-title')), findsNothing);
    expect(server.alerts.single['status'], 'ACKNOWLEDGED', reason: 'ALERT_ACK synced at once (stops the 5-min escalation)');
    expect(find.byKey(const Key('alert-banner')), findsNothing);
    await finish(t);
  });

  testWidgets('reroute (diversion): old vs new stop, no decline; accepted offline, navigation switches, synced later', (t) async {
    await boot(t, status: 'IN_PROGRESS');
    await openTrip(t);
    server.proposeDiversion();
    realtime.inject(const RealtimeEvent('route.proposed', {'tripId': FakeDriverServer.tripId, 'version': 2}));
    await run(t, 15);
    expect(find.byKey(const Key('reroute-reason')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('reroute-old')), matching: find.text('Sambhajinagar DC')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('reroute-new')), matching: find.text('Jalna Fresh Traders')), findsOneWidget);
    expect(find.text('11.2 km longer'), findsOneWidget);
    expect(find.byKey(const Key('reroute-decline')), findsNothing, reason: 'a diversion must be accepted');

    server.online = false;
    await t.tap(find.byKey(const Key('reroute-accept')));
    await run(t, 15);
    expect(navigations.last, (19.8347, 75.8816, 'Jalna Fresh Traders'), reason: 'navigation switched to the new stop');
    expect(find.descendant(of: find.byKey(const Key('next-stop')), matching: find.text('Jalna Fresh Traders')), findsOneWidget);

    server.online = true;
    await drive(t, c.read(syncSchedulerProvider)!.syncNow());
    await run(t, 5);
    expect(server.appliedTypes, contains('ROUTE_ACCEPT'));
    expect(server.routeVersion, 2);
    await finish(t);
  });

  testWidgets('speed lock: above 10 km/h the screen is blocked, Navigate and SOS still work; stopping unlocks it', (t) async {
    await boot(t, status: 'IN_PROGRESS');
    await openTrip(t);
    tracker.emit(_fix(0, 42));
    await run(t, 3);
    expect(find.byKey(const Key('speed-lock')), findsOneWidget);
    expect(find.byKey(const Key('report-incident')).hitTestable(), findsNothing, reason: 'non-essential actions blocked');

    await t.tap(find.byKey(const Key('navigate')).hitTestable());
    await t.pump();
    expect(navigations, hasLength(1));
    await t.tap(find.byKey(const Key('sos')).hitTestable());
    await run(t, 10);
    expect(find.byKey(const Key('sos-sent')), findsOneWidget);
    expect(server.applied.values.where((o) => o['type'] == 'TRIP_EVENT' && (o['payload'] as Map)['type'] == 'SOS'), hasLength(1), reason: 'SOS synced at once with the position');
    await t.tap(find.text('OK'));
    await run(t, 3);

    for (var s = 2; s <= 10; s += 2) {
      tracker.emit(_fix(s, 0));
    }
    await run(t, 3);
    expect(find.byKey(const Key('speed-lock')), findsNothing);
    expect(find.byKey(const Key('report-incident')).hitTestable(), findsOneWidget);
    await finish(t);
  });
}
