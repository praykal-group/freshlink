import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:iccms/apps/manager/screens/admin_reports_screens.dart';
import 'package:iccms/apps/manager/screens/alerts_incidents_screens.dart';
import 'package:iccms/apps/manager/screens/approvals_buyers_screens.dart';
import 'package:iccms/apps/manager/screens/dashboard_screen.dart';
import 'package:iccms/apps/manager/screens/forecast_planning_screens.dart';
import 'package:iccms/apps/manager/screens/trips_screens.dart';
import 'package:iccms/apps/manager/shell.dart';
import 'package:iccms/core/config/app_flavor.dart';
import 'package:iccms/core/providers.dart';

import '../helpers.dart';
import 'fake_manager_server.dart';

ProviderContainer? _live;

/// M13: control-tower screens at text scale 2.0 on a 360×640 dp phone in EN / HI / MR. An
/// overflow fails the test. (The web console at 1280 px is checked in a real browser, TESTING.md.)
void main() {
  Future<void> pump(WidgetTester t, Widget screen, Locale locale, {String role = 'ADMIN'}) async {
    t.view.physicalSize = const Size(1080, 1920);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final server = FakeManagerServer(role: role);
    final c = ProviderContainer(overrides: [
      ...overridesFor(AppFlavor.manager, backend: FakeAuthBackend()..session = true, adapter: server.adapter).cast<Override>(),
      realtimeProvider.overrideWithValue(null),
      mapTilesProvider.overrideWithValue(false),
    ]);
    _live = c;
    addTearDown(() {
      if (_live == c) c.dispose();
    });
    await t.runAsync(() => c.read(localeProvider.notifier).set(locale.languageCode));
    await t.pumpWidget(UncontrolledProviderScope(container: c, child: harness(screen, flavor: AppFlavor.manager, textScale: 2.0, locale: locale)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> end(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    final c = _live;
    _live = null;
    c?.dispose();
    await t.pump(const Duration(milliseconds: 100));
  }

  final screens = <String, Widget>{
    'dashboard': const DashboardScreen(),
    'trips': const TripsScreen(),
    'trip detail with chart': const TripDetailScreen(id: 't-1'),
    'alerts': const AlertsScreen(),
    'incident detail': const IncidentDetailScreen(id: 'inc-1'),
    'forecast': const ForecastScreen(),
    'approvals': const ApprovalsScreen(),
    'buyers': const BuyersScreen(),
    'buyer form': const BuyerFormScreen(),
    'reports': const ReportsScreen(),
    'users': const UsersScreen(),
    'user form': const UserFormScreen(),
    'masters': const MastersScreen(),
    'product form': const MasterFormScreen(entity: 'products'),
    'remote config': const ConfigScreen(),
    'more': const MoreScreen(),
  };

  for (final locale in const [Locale('en'), Locale('hi'), Locale('mr')]) {
    group('manager · text scale 2.0 · ${locale.languageCode}', () {
      screens.forEach((name, screen) {
        testWidgets(name, (t) async {
          await pump(t, screen, locale);
          expect(t.takeException(), isNull);
          await end(t);
        });
      });

      testWidgets('planning after a run (needs table + draft orders)', (t) async {
        await pump(t, const PlanningScreen(), locale);
        await t.tap(find.byKey(const Key('plan-run')));
        for (var i = 0; i < 10; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('order-ORD-20261116-0001'), skipOffstage: false), findsOneWidget);
        await end(t);
      });
    });
  }
}
