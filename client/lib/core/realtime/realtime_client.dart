import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

/// A server event (Section 6.4 Realtime): `alert.raised`, `cargo.status`, `route.proposed`, ...
class RealtimeEvent {
  const RealtimeEvent(this.name, this.data);
  final String name;
  final Map<String, dynamic> data;
}

/// Socket.IO client on `/rt` (Section 10.2 core/realtime): JWT + flavor in the handshake auth,
/// auto-reconnect (fresh token on every attempt), trip rooms re-joined after reconnect.
/// FCM data messages are fed into the same [events] stream by the push service.
class RealtimeClient {
  RealtimeClient({required this.url, required this.flavor, required this.token});

  static const events = [
    'alert.raised', 'alert.updated', 'cargo.status', 'route.proposed', 'route.updated',
    'incident.updated', 'offer.updated', 'trip.updated', 'vehicle.position',
  ];

  final String url;
  final String flavor;
  final String? Function() token;
  io.Socket? _socket;
  final _events = StreamController<RealtimeEvent>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  final Set<String> _trips = {};

  Stream<RealtimeEvent> get stream => _events.stream;
  Stream<bool> get connection => _connected.stream;
  bool get isConnected => _socket?.connected ?? false;

  void connect() {
    if (_socket != null) return;
    final uri = Uri.parse(url);
    final origin = uri.replace(path: '', scheme: uri.scheme == 'wss' ? 'https' : (uri.scheme == 'ws' ? 'http' : uri.scheme)).toString().replaceAll(RegExp(r'/$'), '');
    final s = io.io(
      origin,
      io.OptionBuilder()
          .setPath(uri.path.isEmpty ? '/rt' : uri.path)
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(30000)
          .setAuthFn((cb) => cb({'token': token(), 'flavor': flavor}))
          .build(),
    );
    s.onConnect((_) {
      _connected.add(true);
      for (final t in _trips) {
        s.emitWithAck('trip.join', {'tripId': t}, ack: (_) {});
      }
    });
    s.onDisconnect((_) => _connected.add(false));
    for (final name in events) {
      s.on(name, (data) {
        if (data is Map) _events.add(RealtimeEvent(name, Map<String, dynamic>.from(data)));
      });
    }
    _socket = s..connect();
  }

  /// Follow a trip (driver: own trip; manager: any). Kept across reconnects.
  Future<bool> joinTrip(String tripId) {
    _trips.add(tripId);
    final done = Completer<bool>();
    final s = _socket;
    if (s == null || !s.connected) return Future.value(false);
    s.emitWithAck('trip.join', {'tripId': tripId}, ack: (res) => done.complete(res is Map && res['ok'] == true));
    return done.future.timeout(const Duration(seconds: 10), onTimeout: () => false);
  }

  void leaveTrip(String tripId) {
    _trips.remove(tripId);
    _socket?.emit('trip.leave', {'tripId': tripId});
  }

  /// FCM data messages arriving while the socket is down are delivered the same way.
  void inject(RealtimeEvent e) => _events.add(e);

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }

  Future<void> dispose() async {
    disconnect();
    await _events.close();
    await _connected.close();
  }
}
