import 'package:flutter/painting.dart';

import 'apps/manager/router.dart';
import 'bootstrap.dart';
import 'core/config/app_flavor.dart';

// Imports only apps/manager/ so tree-shaking drops the other dashboards from this APK.
void main() => bootstrap(const AppFlavorConfig(
      flavor: AppFlavor.manager,
      appName: 'I-CCMS Control Tower',
      accent: Color(0xFF5B5BD6),
      router: ManagerRouter(),
    ));
