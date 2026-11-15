import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import 'sync_engine.dart';

/// When to sync (Section 10.2): when the connection comes back, when the app resumes, and every
/// 60 s while online. The driver's foreground service (M12) calls [syncNow] as well.
class SyncScheduler with WidgetsBindingObserver {
  SyncScheduler(this.engine, {Connectivity? connectivity, this.interval = const Duration(seconds: 60)}) : _connectivity = connectivity ?? Connectivity();

  final SyncEngine engine;
  final Connectivity _connectivity;
  final Duration interval;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _timer;
  bool _online = false;
  final _reports = StreamController<SyncReport>.broadcast();

  Stream<SyncReport> get reports => _reports.stream;
  bool get online => _online;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    _online = _isOnline(await _connectivity.checkConnectivity());
    _sub = _connectivity.onConnectivityChanged.listen((r) {
      final was = _online;
      _online = _isOnline(r);
      if (_online && !was) syncNow(); // forced: retries that waited for the network go now
    });
    _timer = Timer.periodic(interval, (_) {
      if (_online) syncNow(force: false);
    });
    if (_online) unawaited(syncNow());
  }

  static bool _isOnline(List<ConnectivityResult> r) => r.any((c) => c != ConnectivityResult.none);

  /// [force] (default): ignore the retry backoff — used on reconnect, resume and "Sync now".
  /// The 60 s timer passes false so a failing server is not hammered.
  Future<SyncReport?> syncNow({bool force = true}) async {
    try {
      final report = await engine.run(force: force);
      if (!_reports.isClosed) _reports.add(report);
      return report;
    } catch (e) {
      debugPrint('sync pass failed: $e');
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) syncNow();
  }

  Future<void> stop() async {
    WidgetsBinding.instance.removeObserver(this);
    await _sub?.cancel();
    _timer?.cancel();
    await _reports.close();
  }
}
