import 'package:flutter/painting.dart';

import 'apps/operator/router.dart';
import 'bootstrap.dart';
import 'core/config/app_flavor.dart';

// Imports only apps/operator/ so tree-shaking drops the other dashboards from this APK.
void main() => bootstrap(const AppFlavorConfig(
      flavor: AppFlavor.operator,
      appName: 'I-CCMS Operator',
      accent: Color(0xFF2E9D5B),
      router: OperatorRouter(),
    ));
