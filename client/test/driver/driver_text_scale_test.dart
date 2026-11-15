import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:iccms/apps/driver/data/models.dart';
import 'package:iccms/apps/driver/providers.dart';
import 'package:iccms/apps/driver/screens/active_trip_screen.dart';
import 'package:iccms/apps/driver/screens/alert_reroute_screens.dart';
import 'package:iccms/apps/driver/screens/cargo_history_screens.dart';
import 'package:iccms/apps/driver/screens/incident_screen.dart';
import 'package:iccms/apps/driver/screens/pre_check_screen.dart';
import 'package:iccms/apps/driver/screens/stop_screen.dart';
import 'package:iccms/apps/driver/screens/today_screen.dart';
import 'package:iccms/core/alarm/alert_alarm.dart';
import 'package:iccms/core/config/app_flavor.dart';
import 'package:iccms/core/location/gps_fix.dart';
import 'package:iccms/core/providers.dart';
import 'package:iccms/core/storage/database.dart';

import '../helpers.dart';
import 'fake_driver_server.dart';

class _Silent implements AlarmOutput {
  @override
  Future<void> startLoop(String title, String body) async {}
  @override
  Future<void> stopLoop() async {}
  @override
  Future<void> ring(String title, String body) async {}
  @override
  Future<void> speak(String text, String languageTag) async {}
  @override
  Future<void> stopSpeaking() async {}
}

/// M12: driver screens at text scale 2.0 on a 360×640 dp phone in EN / HI / MR (DA-NFR: high
/// contrast, big targets; Hindi + Marathi checked for overflow). An overflow fails the test.
ProviderContainer? _live;

void main() {
  final alert = DriverAlert(id: 'al-1', type: 'DRIVER_FIX', severity: 'CRITICAL', message: 'Temperature drifting on trip TRP-20261115-0001: check the door seals.', createdAt: DateTime(2026, 11, 15, 9));

  Future<ProviderContainer> pump(WidgetTester t, Widget screen, Locale locale, {String status = 'IN_PROGRESS', String dropStatus = 'PENDING', bool locked = false, bool proposal = false}) async {
    t.view.physicalSize = const Size(1080, 1920);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final server = FakeDriverServer()..status = status;
    server.stops[1]['status'] = dropStatus;
    if (proposal) server.proposeDiversion();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final c = ProviderContainer(overrides: [
      ...overridesFor(AppFlavor.driver, backend: FakeAuthBackend()..session = true, adapter: server.adapter).cast<Override>(),
      databaseProvider.overrideWithValue(db),
      syncSchedulerProvider.overrideWithValue(null),
      realtimeProvider.overrideWithValue(null),
      tripTrackerProvider.overrideWith((ref) async => null),
      tileProviderProvider.overrideWith((ref) async => null),
      alertAlarmProvider.overrideWithValue(AlertAlarm(_Silent())),
    ]);
    _live = c;
    addTearDown(() {
      if (_live == c) c.dispose();
    });
    await t.runAsync(() => c.read(localeProvider.notifier).set(locale.languageCode));
    await t.pumpWidget(UncontrolledProviderScope(container: c, child: harness(screen, flavor: AppFlavor.driver, textScale: 2.0, locale: locale)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    if (locked) {
      c.read(lastFixProvider.notifier).set(GpsFix(at: DateTime.now(), lat: 19.7, lng: 75.3, speedKmh: 40));
      await t.pump(const Duration(milliseconds: 300));
    }
    return c;
  }

  /// Disposes the container while the test clock runs, so the 60 s polls and the alarm timer
  /// are cancelled before the binding checks for pending timers.
  Future<void> end(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    final c = _live;
    _live = null;
    await c?.read(alertAlarmProvider).stop(); // an overridden value has no onDispose
    c?.dispose();
    await t.pump(const Duration(milliseconds: 100));
  }

  for (final locale in const [Locale('en'), Locale('hi'), Locale('mr')]) {
    group('driver · text scale 2.0 · ${locale.languageCode}', () {
      testWidgets('today: assigned trip, before the pre-check', (t) async {
        await pump(t, const DriverTodayScreen(), locale, status: 'ASSIGNED');
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('trip-card')), findsOneWidget);
        await t.scrollUntilVisible(find.byKey(const Key('module-tag')), 200, scrollable: find.byType(Scrollable).first);
        expect(t.takeException(), isNull);
        await end(t);
      });

      testWidgets('pre-trip check', (t) async {
        await pump(t, const PreCheckScreen(), locale, status: 'ASSIGNED');
        expect(t.takeException(), isNull);
        await end(t);
      });

      testWidgets('active trip (map, next stop, cargo, SOS)', (t) async {
        await pump(t, const ActiveTripScreen(), locale);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('next-stop')), findsOneWidget);
        await end(t);
      });

      testWidgets('active trip under the speed lock', (t) async {
        await pump(t, const ActiveTripScreen(), locale, locked: true);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('speed-lock')), findsOneWidget);
        await end(t);
      });

      testWidgets('cargo status', (t) async {
        await pump(t, const CargoScreen(), locale);
        expect(t.takeException(), isNull);
        await end(t);
      });

      testWidgets('critical alert', (t) async {
        await pump(t, AlertScreen(alert: alert), locale);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('ack')), findsOneWidget);
        await end(t);
      });

      testWidgets('reroute proposal', (t) async {
        final c = await pump(t, const SizedBox(), locale, proposal: true);
        final p = await t.runAsync(() => c.read(driverRepositoryProvider).proposal(FakeDriverServer.tripId));
        await t.pumpWidget(UncontrolledProviderScope(container: c, child: harness(RerouteScreen(proposal: p!), flavor: AppFlavor.driver, textScale: 2.0, locale: locale)));
        await t.pump(const Duration(milliseconds: 300));
        expect(t.takeException(), isNull);
        await t.scrollUntilVisible(find.byKey(const Key('reroute-accept')), 200, scrollable: find.byType(Scrollable).first);
        expect(t.takeException(), isNull);
        await end(t);
      });

      testWidgets('report incident', (t) async {
        await pump(t, const IncidentScreen(), locale);
        expect(t.takeException(), isNull);
        await end(t);
      });

      testWidgets('stop: arrive', (t) async {
        await pump(t, const StopScreen(stopId: FakeDriverServer.dropId), locale);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('arrive')), findsOneWidget);
        await end(t);
      });

      testWidgets('stop: proof of delivery with a partial line', (t) async {
        await pump(t, const StopScreen(stopId: FakeDriverServer.dropId), locale, dropStatus: 'ARRIVED');
        expect(t.takeException(), isNull);
        final partial = find.byKey(const Key('pod-outcome-FSH-20261115-DCK-PTN-0002'));
        await t.scrollUntilVisible(partial, 200, scrollable: find.byType(Scrollable).first);
        await t.tap(find.descendant(of: partial, matching: find.byIcon(Icons.remove_rounded))); // Partial: kg + reason fields appear
        await t.pump(const Duration(milliseconds: 300));
        expect(t.takeException(), isNull);
        await end(t);
      });

      testWidgets('history and pending uploads', (t) async {
        await pump(t, const HistoryScreen(), locale);
        expect(t.takeException(), isNull);
        await end(t);
      });
    });
  }
}
