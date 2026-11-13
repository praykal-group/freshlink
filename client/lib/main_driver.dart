import 'package:flutter/painting.dart';

import 'apps/driver/router.dart';
import 'bootstrap.dart';
import 'core/config/app_flavor.dart';

// Imports only apps/driver/ so tree-shaking drops the other dashboards from this APK.
void main() => bootstrap(const AppFlavorConfig(
      flavor: AppFlavor.driver,
      appName: 'I-CCMS Driver',
      accent: Color(0xFF12C2E9),
      router: DriverRouter(),
    ));
