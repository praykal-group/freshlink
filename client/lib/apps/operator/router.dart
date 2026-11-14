import 'package:go_router/go_router.dart';

import '../../core/config/app_flavor.dart';
import '../../shared/screens/app_screens.dart';
import 'module_tag.dart';

/// I-CCMS Operator routes. The shared routes (splash, login, settings, sync queue, ...) come from core;
/// this file adds the flavor's own screens (M11). Imported only by main_operator.dart (Section 11).
class OperatorRouter extends FlavorRouter {
  const OperatorRouter();

  @override
  String get homePath => '/home';

  @override
  List<RouteBase> get routes => [
        GoRoute(path: '/home', builder: (_, _) => const FlavorHomeScreen(moduleTag: kModuleTag)),
      ];
}
