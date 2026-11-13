import 'package:flutter/widgets.dart';

import '../../core/config/app_flavor.dart';
import '../../shared/screens/placeholder_screen.dart';
import 'module_tag.dart';

class OperatorRouter extends FlavorRouter {
  const OperatorRouter();

  @override
  String get initialRoute => '/';

  @override
  Map<String, WidgetBuilder> get routes => {
        '/': (_) => const PlaceholderScreen(title: 'I-CCMS Operator', moduleTag: kModuleTag),
      };
}
