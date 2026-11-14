import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/app_flavor.dart';
import '../config/env.dart';
import '../realtime/realtime_client.dart';

/// Android channels: critical cargo alerts are high importance (heads-up + sound).
const _critical = AndroidNotificationChannel('iccms_critical', 'Critical alerts', description: 'Temperature, SOS and reroute alerts', importance: Importance.max);
const _general = AndroidNotificationChannel('iccms_general', 'Updates', description: 'Trips, approvals and app updates', importance: Importance.defaultImportance);

/// Background FCM handler (top level, its own isolate). Data messages are shown as notifications;
/// the app replays the event when it opens.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await PushService.showLocal(message);
}

/// FCM + local notifications + Crashlytics (Section 10.2, 15). Firebase options come from the env
/// file, not google-services.json (D-120); without them push is off and the app still works (the
/// backend falls back to SMS for drivers).
class PushService {
  PushService(this.flavor);

  final AppFlavor flavor;
  static final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  String? _token;

  bool get enabled => _ready;

  Future<void> init({RealtimeClient? realtime}) async {
    if (kIsWeb || !Env.firebaseConfigured(flavor)) {
      debugPrint('push: Firebase not configured for ${flavor.name}; push and Crashlytics are off');
      return;
    }
    await Firebase.initializeApp(
      options: FirebaseOptions(apiKey: Env.firebaseApiKey, appId: Env.firebaseAppId(flavor), messagingSenderId: Env.firebaseSenderId, projectId: Env.firebaseProjectId),
    );
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    await _initLocal();
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    final fm = FirebaseMessaging.instance;
    await fm.requestPermission();
    // Classic FCM registration token: the backend (firebase-admin) sends to tokens. The newer
    // register()/onRegistered FID direct-send flow would need a backend change (D-121).
    // ignore: deprecated_member_use
    _token = await fm.getToken();
    FirebaseMessaging.onMessage.listen((m) {
      // Foreground: the socket usually delivered it already; feed the stream (deduped by the
      // feature providers on ids) and show it if it is critical.
      final event = m.data['event'];
      if (event is String && realtime != null) realtime.inject(RealtimeEvent(event, Map<String, dynamic>.from(m.data)));
      if (m.data['critical'] == 'true') showLocal(m);
    });
    _ready = true;
  }

  static Future<void> _initLocal() async {
    await _local.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_critical);
    await android?.createNotificationChannel(_general);
  }

  static Future<void> showLocal(RemoteMessage m) async {
    final title = m.notification?.title ?? m.data['title'] as String?;
    final body = m.notification?.body ?? m.data['body'] as String?;
    if (title == null) return;
    final critical = m.data['critical'] == 'true';
    final channel = critical ? _critical : _general;
    await _local.show(
      id: m.hashCode & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: AndroidNotificationDetails(channel.id, channel.name, importance: channel.importance, priority: critical ? Priority.max : Priority.defaultPriority)),
    );
  }

  /// Sent with `POST /me/session`.
  Future<String?> token() async => _token;

  /// Non-fatal errors with an AppException code (no PII, Section 15).
  void recordNonFatal(Object error, StackTrace? stack, {String? code}) {
    if (!_ready) return;
    FirebaseCrashlytics.instance.recordError(error, stack, reason: code, fatal: false);
  }
}
