import 'package:flutter/widgets.dart';

enum AppFlavor { driver, operator, manager }

/// A flavor's route table. Each `apps/<flavor>/router.dart` provides one;
/// `core/` only knows this interface, never the concrete flavor code.
abstract class FlavorRouter {
  const FlavorRouter();

  String get initialRoute;
  Map<String, WidgetBuilder> get routes;
}

/// Everything `bootstrap()` needs to start one of the three apps.
class AppFlavorConfig {
  const AppFlavorConfig({
    required this.flavor,
    required this.appName,
    required this.accent,
    required this.router,
  });

  final AppFlavor flavor;
  final String appName;
  final Color accent;
  final FlavorRouter router;

  /// Sent as `X-App-Flavor` on every API call (Section 6.1).
  String get headerValue => flavor.name;
}
