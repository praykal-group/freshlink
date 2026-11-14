import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/screens/app_screens.dart';
import '../../shared/screens/auth_screens.dart';
import '../auth/session.dart';
import '../providers.dart';

const _authPaths = {'/splash', '/login', '/login/phone', '/otp', '/verify-email'};

/// Shared routes + the flavor's own routes, guarded by the session (Section 10.3):
/// 426 → update screen; restoring → splash; signed out → login; unconfirmed email → verify;
/// signed in → the flavor home (never back to the auth screens).
final routerProvider = Provider<GoRouter>((ref) {
  final config = ref.watch(flavorConfigProvider);
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.listen(upgradeRequiredProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (ref.read(upgradeRequiredProvider)) return loc == '/update-required' ? null : '/update-required';
      final session = ref.read(sessionProvider);
      switch (session) {
        case SessionUnknown():
          return loc == '/splash' ? null : '/splash';
        case SignedOut():
          return {'/login', '/login/phone', '/otp', '/verify-email'}.contains(loc) ? null : '/login';
        case NeedsEmailVerification():
          return loc == '/verify-email' ? null : '/verify-email';
        case SignedIn():
          return _authPaths.contains(loc) ? config.router.homePath : null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/login/phone', builder: (_, _) => const PhoneLoginScreen(showBack: true)),
      GoRoute(path: '/otp', builder: (_, s) => OtpScreen(phone: s.extra as String? ?? '')),
      GoRoute(path: '/verify-email', builder: (_, s) => VerifyEmailScreen(email: s.extra as String?)),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/sync-queue', builder: (_, _) => const SyncQueueScreen()),
      GoRoute(path: '/update-required', builder: (_, _) => const UpdateRequiredScreen()),
      ...config.router.routes,
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
