import 'package:flutter/widgets.dart';

import '../../core/config/app_flavor.dart';
import '../../shared/screens/placeholder_screen.dart';
import 'module_tag.dart';

class ManagerRouter extends FlavorRouter {
  const ManagerRouter();

  @override
  String get initialRoute => '/';

  @override
  Map<String, WidgetBuilder> get routes => {
        '/': (_) => const PlaceholderScreen(title: 'I-CCMS Control Tower', moduleTag: kModuleTag),
      };
}
