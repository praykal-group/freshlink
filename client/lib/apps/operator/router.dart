import 'package:go_router/go_router.dart';

import '../../core/config/app_flavor.dart';
import 'screens/batches_screens.dart';
import 'screens/home_screen.dart';
import 'screens/receive_load_screens.dart';
import 'screens/wizard_screen.dart';

/// Operator APK routes (Section 10.4). The shared routes (splash, login, settings, sync queue, ...)
/// come from core. Imported only by main_operator.dart (Section 11).
class OperatorRouter extends FlavorRouter {
  const OperatorRouter();

  @override
  String get homePath => '/home';

  @override
  List<RouteBase> get routes => [
        GoRoute(path: '/home', builder: (_, _) => const OperatorHomeScreen()),
        GoRoute(path: '/batch/new/:kind', builder: (_, s) => BatchWizardScreen(category: s.pathParameters['kind'] == 'produce' ? 'PRODUCE' : 'FISH')),
        GoRoute(path: '/batch/resume', builder: (_, _) => const BatchWizardScreen(category: 'FISH', resume: true)),
        GoRoute(path: '/batches', builder: (_, _) => const BatchListScreen()),
        GoRoute(path: '/batches/:id', builder: (_, s) => BatchDetailScreen(id: s.pathParameters['id']!)),
        GoRoute(path: '/receive', builder: (_, _) => const ReceiveScreen()),
        GoRoute(path: '/load', builder: (_, _) => const LoadTruckScreen()),
        GoRoute(path: '/printer', builder: (_, _) => const PrinterSetupScreen()),
      ];
}
