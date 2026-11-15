import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session.dart';
import '../../core/providers.dart';
import 'data/manager_repository.dart';
import 'data/models.dart';

final managerRepositoryProvider = Provider<ManagerRepository>((ref) => ManagerRepository(ref.watch(apiClientProvider)));

/// ADMIN sees masters, users and remote config (Section 10.6 #8/#9); MANAGER does not — and the
/// API refuses them anyway (403, Section 6.3).
final isAdminProvider = Provider<bool>((ref) {
  final s = ref.watch(sessionProvider);
  return s is SignedIn && s.me.role == 'ADMIN';
});

/// Dashboard (Section 10.6 #1): KPIs + vehicles. Refetched on `alert.raised` / `incident.updated`
/// (a live alert shows within seconds), markers moved by `vehicle.position`, polled every 60 s.
class SummaryController extends AsyncNotifier<ControlSummary> {
  @override
  Future<ControlSummary> build() {
    final rt = ref.watch(realtimeProvider);
    final sub = rt?.stream.listen((e) {
      if (e.name == 'vehicle.position') {
        final v = state.value;
        if (v != null) state = AsyncData(v.withPosition(e.data));
      } else if (e.name == 'alert.raised' || e.name == 'alert.updated' || e.name == 'incident.updated' || e.name == 'trip.updated') {
        unawaited(refresh());
      }
    });
    final timer = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
    ref.onDispose(() {
      sub?.cancel();
      timer.cancel();
    });
    return ref.read(managerRepositoryProvider).summary();
  }

  Future<void> refresh() async {
    final next = await AsyncValue.guard(() => ref.read(managerRepositoryProvider).summary());
    if (ref.mounted) state = next.hasValue ? next : (state.hasValue ? state : next);
  }
}

final summaryProvider = AsyncNotifierProvider.autoDispose<SummaryController, ControlSummary>(SummaryController.new);

/// Live alert list (Section 10.6 #3): `alert.raised` puts the new alert on top at once.
class LiveAlertsController extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    final sub = ref.watch(realtimeProvider)?.stream.listen((e) {
      final list = state.value;
      if (list == null) return;
      final id = '${e.data['alertId'] ?? e.data['id']}';
      if (e.name == 'alert.raised' && !list.any((a) => a['id'] == id)) {
        state = AsyncData([{...e.data, 'id': id, 'status': e.data['status'] ?? 'OPEN'}, ...list]);
      } else if (e.name == 'alert.updated') {
        state = AsyncData([for (final a in list) a['id'] == id ? {...a, ...e.data, 'id': id} : a]);
      }
    });
    ref.onDispose(() => sub?.cancel());
    return (await ref.read(managerRepositoryProvider).alerts()).items;
  }

  Future<void> refresh() async => state = await AsyncValue.guard(() async => (await ref.read(managerRepositoryProvider).alerts()).items);
}

final liveAlertsProvider = AsyncNotifierProvider.autoDispose<LiveAlertsController, List<Map<String, dynamic>>>(LiveAlertsController.new);

/// Master lists for pickers (sites, products, storage units, config) from the bundle.
final bundleProvider = FutureProvider<Map<String, dynamic>>((ref) => ref.watch(managerRepositoryProvider).bundle());

final sitesProvider = Provider<List<Map<String, dynamic>>>((ref) => maps(ref.watch(bundleProvider).value?['sites']));
final productsProvider = Provider<List<Map<String, dynamic>>>((ref) => maps(ref.watch(bundleProvider).value?['products']));
