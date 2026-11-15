import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:iccms/apps/manager/router.dart';
import 'package:iccms/apps/manager/screens/dashboard_screen.dart';
import 'package:iccms/bootstrap.dart';
import 'package:iccms/core/config/app_flavor.dart';
import 'package:iccms/core/providers.dart';
import 'package:iccms/core/realtime/realtime_client.dart';
import 'package:iccms/core/router/app_router.dart';

import '../helpers.dart';
import 'fake_manager_server.dart';

/// Section 16 / M13: the control-tower screens + API client against a scripted backend.
void main() {
  late FakeManagerServer server;
  late ProviderContainer c;
  late RealtimeClient realtime;

  Future<void> run(WidgetTester t, [int ticks = 10]) async {
    for (var i = 0; i < ticks; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> boot(WidgetTester t, {String role = 'MANAGER', Size size = const Size(1280, 900)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    server = FakeManagerServer(role: role);
    realtime = RealtimeClient(url: 'ws://unused', flavor: 'manager-web', token: () => null);
    c = ProviderContainer(overrides: [
      ...overridesFor(AppFlavor.manager, backend: FakeAuthBackend()..session = true, adapter: server.adapter, router: const ManagerRouter()).cast<Override>(),
      realtimeProvider.overrideWithValue(realtime),
      mapTilesProvider.overrideWithValue(false),
    ]);
    await t.pumpWidget(UncontrolledProviderScope(container: c, child: const IccmsApp()));
    await run(t, 20);
  }

  /// Disposes while the test clock runs (the 60 s dashboard poll is cancelled).
  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await t.pump(const Duration(milliseconds: 100));
  }

  Future<void> go(WidgetTester t, String path) async {
    c.read(routerProvider).go(path);
    await run(t, 15);
  }

  Future<void> pickFromDropdown(WidgetTester t, Key field, String item) async {
    await t.tap(find.byKey(field));
    await run(t, 3);
    await t.tap(find.text(item).last);
    await run(t, 3);
  }

  testWidgets('planning: run → edit a draft → approve all → build routes → assign driver + vehicle', (t) async {
    await boot(t);
    await go(t, '/planning');
    await t.tap(find.byKey(const Key('plan-run')));
    await run(t, 15);
    expect(server.calls, contains('POST /planning/run'));
    expect(find.text('DC-CSN'), findsOneWidget, reason: 'need per centre');
    expect(find.byKey(const Key('order-ORD-20261116-0001')), findsOneWidget);
    expect(find.text('Paithan Dock → Sambhajinagar DC'), findsNWidgets(2));

    // edit the quantity of a draft
    await t.tap(find.byKey(const Key('edit-ORD-20261116-0001')));
    await run(t, 3);
    await t.enterText(find.byKey(const Key('order-qty')), '450');
    await t.tap(find.byKey(const Key('order-qty-save')));
    await run(t, 10);
    expect(server.bodies['PATCH /orders/o-1'], {'quantityKg': 450.0});
    expect(find.text('Rohu · 450 kg'), findsOneWidget);

    await t.tap(find.byKey(const Key('approve-all')));
    await run(t, 15);
    expect(server.orders.map((o) => o['status']), ['APPROVED', 'APPROVED']);

    await t.tap(find.byKey(const Key('build-routes')));
    await run(t, 15);
    expect(server.bodies['POST /planning/routes'], {'date': isA<String>(), 'depotSiteId': FakeManagerServer.dock});
    expect(find.byKey(const Key('built-TRP-20261116-0001')), findsOneWidget);

    await t.tap(find.byKey(const Key('assign-TRP-20261116-0001')));
    await run(t, 10);
    expect(find.text('Sunil Pawar (TRP-20261115-0001)'), findsNothing, reason: 'dropdown closed');
    await pickFromDropdown(t, const Key('assign-driver'), 'Ravi Deshmukh');
    await pickFromDropdown(t, const Key('assign-vehicle'), 'MH20-RF-1003 · 3,000 kg');
    await t.tap(find.byKey(const Key('assign-save')));
    await run(t, 10);
    expect(server.assigned['t-new'], {'driverId': 'd-1', 'vehicleId': 'v3'});
    await finish(t);
  });

  testWidgets('a MANAGER never sees or opens admin screens; an ADMIN does', (t) async {
    await boot(t);
    expect(find.byKey(const Key('nav-rail')), findsOneWidget);
    for (final p in ['/admin/masters', '/admin/users', '/admin/config']) {
      expect(find.byKey(Key('nav-$p')), findsNothing);
      await go(t, p);
      expect(c.read(routerProvider).routerDelegate.currentConfiguration.uri.path, '/home', reason: '$p redirects a manager');
    }
    expect(server.calls.where((x) => x.contains('/admin/')), isEmpty, reason: 'no admin call was even attempted');
    await finish(t);

    await boot(t, role: 'ADMIN');
    expect(find.byKey(const Key('nav-/admin/users')), findsOneWidget);
    await t.tap(find.byKey(const Key('nav-/admin/users')));
    await run(t, 15);
    expect(find.byKey(const Key('user-Ravi Deshmukh')), findsOneWidget);
    await finish(t);
  });

  testWidgets('a live alert appears on the dashboard at once (well inside 5 s) and the KPIs refresh', (t) async {
    await boot(t);
    expect(find.descendant(of: find.byKey(const Key('kpi-critical')), matching: find.text('1')), findsOneWidget);
    final before = server.calls.where((x) => x == 'GET /control/summary').length;

    server.criticalAlerts = 2;
    realtime.inject(const RealtimeEvent('alert.raised', {'alertId': 'al-2', 'type': 'SPOILAGE_RISK', 'severity': 'CRITICAL', 'tripId': 't-2', 'message': 'Batch FSH-0007 will spoil before the drop', 'createdAt': '2026-11-15T04:30:00Z'}));
    await run(t, 10); // 1 s of test time
    expect(find.byKey(const Key('dash-alert-al-2')), findsOneWidget);
    expect(server.calls.where((x) => x == 'GET /control/summary').length, before + 1);
    expect(find.descendant(of: find.byKey(const Key('kpi-critical')), matching: find.text('2')), findsOneWidget);

    // a moving truck moves without a refetch
    realtime.inject(const RealtimeEvent('vehicle.position', {'vehicleId': 'v2', 'lat': 19.9, 'lng': 75.5}));
    await run(t, 3);
    expect(find.byKey(const Key('marker-MH20-RF-1002')), findsOneWidget);
    await finish(t);
  });

  testWidgets('charts show exactly the API data: trip temperature with its band, forecast bars + whiskers', (t) async {
    await boot(t);
    await go(t, '/trips/t-1');
    final line = t.widget<LineChart>(find.byKey(const Key('temp-chart')));
    final spots = line.data.lineBarsData.single.spots;
    final api = server.telemetry['points'] as List;
    expect(spots.length, api.length);
    expect([for (final s in spots) s.y], [for (final p in api) (p as Map)['temp_c']]);
    expect(line.data.extraLinesData.horizontalLines.map((h) => h.y), [0, 4], reason: 'the safe band from the API');
    expect(find.text('1 of 12 readings outside the safe range'), findsOneWidget);

    await go(t, '/forecast');
    await pickFromDropdown(t, const Key('fc-site'), 'Sambhajinagar DC');
    await pickFromDropdown(t, const Key('fc-product'), 'Rohu');
    await run(t, 10);
    final bars = t.widget<BarChart>(find.byKey(const Key('forecast-chart')));
    expect(bars.data.barGroups.length, 7);
    for (var i = 0; i < 7; i++) {
      final f = server.forecast[i];
      final rods = bars.data.barGroups[i].barRods;
      expect([rods[0].toY, rods[1].fromY, rods[1].toY], [f['predictedKg'], f['lowerKg'], f['upperKg']]);
    }
    await finish(t);
  });

  testWidgets('phone layout: bottom navigation + More; incident detail with log, offers and manual actions', (t) async {
    await boot(t, size: const Size(390, 844));
    expect(find.byKey(const Key('nav-bar')), findsOneWidget);
    expect(find.byKey(const Key('nav-rail')), findsNothing);
    await t.tap(find.byKey(const Key('nav-/more')));
    await run(t, 10);
    expect(find.byKey(const Key('more-/buyers')), findsOneWidget);
    expect(find.byKey(const Key('more-/admin/users')), findsNothing);

    await go(t, '/incidents/inc-1');
    expect(find.byKey(const Key('log-CLASSIFIED')), findsOneWidget);
    expect(find.byKey(const Key('offer-EXPIRED')), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const Key('action-REPLAN')), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.byKey(const Key('action-REPLAN')));
    await run(t, 3);
    await t.tap(find.byKey(const Key('confirm-ok')));
    await run(t, 10);
    expect(server.bodies['POST /incidents/inc-1/action'], {'action': 'REPLAN'});
    await finish(t);
  });
}
