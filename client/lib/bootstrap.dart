import 'package:flutter/material.dart';

import 'core/config/app_flavor.dart';

/// Shared start-up for every flavor. Supabase, storage, sync and FCM init are added in M10.
Future<void> bootstrap(AppFlavorConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(IccmsApp(config: config));
}

class IccmsApp extends StatelessWidget {
  const IccmsApp({super.key, required this.config});

  final AppFlavorConfig config;

  @override
  Widget build(BuildContext context) {
    // Placeholder theme from the flavor accent; full design tokens (Section 13) come in M10.
    ThemeData themeFor(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: config.accent, brightness: b),
          useMaterial3: true,
        );
    return MaterialApp(
      title: config.appName,
      debugShowCheckedModeBanner: false,
      theme: themeFor(Brightness.light),
      darkTheme: themeFor(Brightness.dark),
      initialRoute: config.router.initialRoute,
      routes: config.router.routes,
    );
  }
}
