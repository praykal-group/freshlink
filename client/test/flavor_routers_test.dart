import 'package:flutter_test/flutter_test.dart';
import 'package:iccms/apps/driver/router.dart';
import 'package:iccms/apps/manager/router.dart';
import 'package:iccms/apps/operator/router.dart';
import 'package:iccms/bootstrap.dart';
import 'package:iccms/core/config/app_flavor.dart';
import 'package:flutter/painting.dart';

void main() {
  final cases = <String, FlavorRouter>{
    'driver': const DriverRouter(),
    'operator': const OperatorRouter(),
    'manager': const ManagerRouter(),
  };
  cases.forEach((flavor, router) {
    testWidgets('$flavor app shows its own module tag', (tester) async {
      await tester.pumpWidget(IccmsApp(
        config: AppFlavorConfig(
          flavor: AppFlavor.values.byName(flavor),
          appName: flavor,
          accent: const Color(0xFF0B4F6C),
          router: router,
        ),
      ));
      expect(find.text('iccms-module-$flavor'), findsOneWidget);
    });
  });
}
