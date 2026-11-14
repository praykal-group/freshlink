import 'package:go_router/go_router.dart';

import '../../core/config/app_flavor.dart';
import '../../shared/screens/app_screens.dart';
import 'module_tag.dart';

/// I-CCMS Driver routes. The shared routes (splash, login, settings, sync queue, ...) come from core;
/// this file adds the flavor's own screens (M12). Imported only by main_driver.dart (Section 11).
class DriverRouter extends FlavorRouter {
  const DriverRouter();

  @override
  String get homePath => '/home';

  @override
  List<RouteBase> get routes => [
        GoRoute(path: '/home', builder: (_, _) => const FlavorHomeScreen(moduleTag: kModuleTag)),
      ];
}
