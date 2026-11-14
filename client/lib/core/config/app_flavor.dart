import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum AppFlavor { driver, operator, manager }

/// How a flavor's users sign in (Section 10.3, AUTH-02/03).
enum LoginMethod { phoneOtp, managerEmailGoogle }

extension AppFlavorX on AppFlavor {
  /// Server role names allowed in this app (Section 6.2 FlavorRoleGuard). Checked by the server;
  /// the app checks too, only to show a clear message sooner.
  Set<String> get allowedRoles => switch (this) {
        AppFlavor.driver => {'DRIVER'},
        AppFlavor.operator => {'OPERATOR'},
        AppFlavor.manager => {'MANAGER', 'ADMIN'},
      };

  LoginMethod get loginMethod => this == AppFlavor.manager ? LoginMethod.managerEmailGoogle : LoginMethod.phoneOtp;

  /// Driver and operator queue writes offline; the manager app is online-only (Section 10.6).
  bool get hasOfflineOutbox => this != AppFlavor.manager;

  /// Driver/operator use bigger touch targets (56 dp) for gloves and moving cabs (Section 13.3).
  bool get largeTargets => this != AppFlavor.manager;

  /// Section 13.1 defaults: driver follows the system (dark at night in the cab), operator light
  /// high-contrast (sunlight), manager follows the system.
  ThemeMode get defaultThemeMode => this == AppFlavor.operator ? ThemeMode.light : ThemeMode.system;
}

/// A flavor's screens. Each `apps/<flavor>/router.dart` provides one; `core/` and `shared/` only know
/// this interface, never the concrete flavor code (Section 11 isolation).
abstract class FlavorRouter {
  const FlavorRouter();

  /// Where a signed-in user lands.
  String get homePath;

  /// The flavor's own routes; the shared routes (splash, login, settings, ...) are added by core.
  List<RouteBase> get routes;
}

/// Everything `bootstrap()` needs to start one of the three apps.
class AppFlavorConfig {
  const AppFlavorConfig({required this.flavor, required this.appName, required this.router});

  final AppFlavor flavor;
  final String appName;
  final FlavorRouter router;

  /// Sent as `X-App-Flavor` (Section 6.1). The manager flavor running in a browser is `web`.
  String headerValue({required bool isWeb}) => flavor == AppFlavor.manager && isWeb ? 'web' : flavor.name;
}
