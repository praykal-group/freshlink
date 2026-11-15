import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_flavor.dart';
import 'data/models.dart';
import 'screens/active_trip_screen.dart';
import 'screens/alert_reroute_screens.dart';
import 'screens/cargo_history_screens.dart';
import 'screens/incident_screen.dart';
import 'screens/pre_check_screen.dart';
import 'screens/stop_screen.dart';
import 'screens/today_screen.dart';

/// I-CCMS Driver routes (Section 10.5). The shared routes (splash, login, settings, sync queue, ...)
/// come from core. Imported only by main_driver.dart (Section 11).
class DriverRouter extends FlavorRouter {
  const DriverRouter();

  @override
  String get homePath => '/home';

  @override
  List<RouteBase> get routes => [
        GoRoute(path: '/home', builder: (_, _) => const DriverTodayScreen()),
        GoRoute(path: '/pre-check', builder: (_, _) => const PreCheckScreen()),
        GoRoute(path: '/trip', builder: (_, _) => const ActiveTripScreen()),
        GoRoute(path: '/cargo', builder: (_, _) => const CargoScreen()),
        GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
        GoRoute(path: '/incident', builder: (_, _) => const IncidentScreen()),
        GoRoute(path: '/stop/:id', builder: (_, s) => StopScreen(stopId: s.pathParameters['id']!)),
        // alert / proposal objects come with the push; a missing extra (restored route) goes home
        GoRoute(path: '/alert', builder: (_, s) => s.extra is DriverAlert ? AlertScreen(alert: s.extra! as DriverAlert) : const _Home()),
        GoRoute(path: '/reroute', builder: (_, s) => s.extra is RouteProposal ? RerouteScreen(proposal: s.extra! as RouteProposal) : const _Home()),
      ];
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => const DriverTodayScreen();
}
