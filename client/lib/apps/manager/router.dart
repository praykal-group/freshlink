import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_flavor.dart';
import 'providers.dart';
import 'screens/admin_reports_screens.dart';
import 'screens/alerts_incidents_screens.dart';
import 'screens/approvals_buyers_screens.dart';
import 'screens/dashboard_screen.dart';
import 'screens/forecast_planning_screens.dart';
import 'screens/trips_screens.dart';
import 'shell.dart';

/// I-CCMS Control Tower routes (Section 10.6), shared by the APK and the web console. The shared
/// routes (splash, login, settings, ...) come from core. Imported only by main_manager.dart.
class ManagerRouter extends FlavorRouter {
  const ManagerRouter();

  @override
  String get homePath => '/home';

  /// ADMIN-only screens: a MANAGER who opens the URL lands on the dashboard (the API refuses
  /// these calls with 403 as well, Section 6.3).
  static String? adminOnly(BuildContext context, GoRouterState _) => ProviderScope.containerOf(context).read(isAdminProvider) ? null : '/home';

  @override
  List<RouteBase> get routes => [
        ShellRoute(
          builder: (_, state, child) => ManagerShell(location: state.uri.path, child: child),
          routes: [
            GoRoute(path: '/home', builder: (_, _) => const DashboardScreen()),
            GoRoute(path: '/trips', builder: (_, _) => const TripsScreen()),
            GoRoute(path: '/trips/:id', builder: (_, s) => TripDetailScreen(id: s.pathParameters['id']!)),
            GoRoute(path: '/alerts', builder: (_, _) => const AlertsScreen()),
            GoRoute(path: '/incidents/:id', builder: (_, s) => IncidentDetailScreen(id: s.pathParameters['id']!)),
            GoRoute(path: '/forecast', builder: (_, _) => const ForecastScreen()),
            GoRoute(path: '/planning', builder: (_, _) => const PlanningScreen()),
            GoRoute(path: '/approvals', builder: (_, _) => const ApprovalsScreen()),
            GoRoute(path: '/buyers', builder: (_, _) => const BuyersScreen()),
            GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen()),
            GoRoute(path: '/releases', builder: (_, _) => const ReleasesScreen()),
            GoRoute(path: '/more', builder: (_, _) => const MoreScreen()),
            GoRoute(path: '/admin/masters', redirect: adminOnly, builder: (_, _) => const MastersScreen()),
            GoRoute(path: '/admin/users', redirect: adminOnly, builder: (_, _) => const UsersScreen()),
            GoRoute(path: '/admin/config', redirect: adminOnly, builder: (_, _) => const ConfigScreen()),
          ],
        ),
      ];
}
