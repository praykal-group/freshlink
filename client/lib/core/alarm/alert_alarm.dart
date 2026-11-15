import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Sound + voice for a critical cargo alert. The app uses [DeviceAlarmOutput]; tests a recorder.
abstract class AlarmOutput {
  /// Starts the looping alarm sound (until [stopLoop]).
  Future<void> startLoop(String title, String body);
  Future<void> stopLoop();

  /// One alarm sound (the 30 s reminders after the first 2 minutes).
  Future<void> ring(String title, String body);

  /// TTS in the driver's language (`en-IN`, `hi-IN`, `mr-IN`).
  Future<void> speak(String text, String languageTag);
  Future<void> stopSpeaking();
}

/// Section 10.5 #5 / DA-FR-06: the alarm loops until acknowledged, at most [loopFor] (2 min);
/// after that it rings and repeats the voice prompt every [remindEvery] (30 s) until the driver
/// acknowledges (DA-FR-07: the server escalates to the manager after 5 min without an ack).
class AlertAlarm {
  AlertAlarm(this.output, {this.loopFor = const Duration(minutes: 2), this.remindEvery = const Duration(seconds: 30)});

  final AlarmOutput output;
  final Duration loopFor;
  final Duration remindEvery;

  Timer? _loopEnd;
  Timer? _reminder;
  String? _activeId;

  String? get activeAlertId => _activeId;

  /// Starts (or keeps) the alarm for [alertId]; a second alert replaces the first one's prompt.
  Future<void> start({required String alertId, required String title, required String body, required String speech, required String languageTag}) async {
    if (_activeId == alertId) return;
    await stop();
    _activeId = alertId;
    await output.startLoop(title, body);
    await output.speak(speech, languageTag);
    _loopEnd = Timer(loopFor, () async {
      await output.stopLoop();
      _reminder = Timer.periodic(remindEvery, (_) async {
        await output.ring(title, body);
        await output.speak(speech, languageTag);
      });
    });
  }

  /// Acknowledged (or resolved by the system): silence everything.
  Future<void> stop() async {
    _loopEnd?.cancel();
    _reminder?.cancel();
    _loopEnd = _reminder = null;
    if (_activeId == null) return;
    _activeId = null;
    await output.stopLoop();
    await output.stopSpeaking();
  }
}

/// Alarm through a notification on the ALARM audio stream: `FLAG_INSISTENT` repeats its sound until
/// it is cancelled, and it rings even with the app in the background or the screen off. No extra
/// audio package (D-144).
class DeviceAlarmOutput implements AlarmOutput {
  DeviceAlarmOutput({FlutterLocalNotificationsPlugin? notifications, FlutterTts? tts})
      : _n = notifications ?? FlutterLocalNotificationsPlugin(),
        _tts = tts ?? FlutterTts();

  final FlutterLocalNotificationsPlugin _n;
  final FlutterTts _tts;
  static const _loopId = 9101;
  static const _ringId = 9102;
  static const _flagInsistent = 4; // android.app.Notification.FLAG_INSISTENT

  static const _channel = AndroidNotificationChannel(
    'iccms_alarm',
    'Cargo alarm',
    description: 'Critical cargo alerts that need an acknowledgement',
    importance: Importance.max,
    playSound: true,
    sound: UriAndroidNotificationSound('content://settings/system/alarm_alert'),
    audioAttributesUsage: AudioAttributesUsage.alarm,
    enableVibration: true,
  );

  AndroidNotificationDetails _details({required bool insistent}) => AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        sound: _channel.sound,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        fullScreenIntent: true,
        ongoing: insistent,
        autoCancel: false,
        additionalFlags: insistent ? Int32List.fromList([_flagInsistent]) : null,
      );

  @override
  Future<void> startLoop(String title, String body) async {
    await _n.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(_channel);
    await _n.show(id: _loopId, title: title, body: body, notificationDetails: NotificationDetails(android: _details(insistent: true)));
  }

  @override
  Future<void> stopLoop() async {
    await _n.cancel(id: _loopId);
    await _n.cancel(id: _ringId);
  }

  @override
  Future<void> ring(String title, String body) => _n.show(id: _ringId, title: title, body: body, notificationDetails: NotificationDetails(android: _details(insistent: false)));

  @override
  Future<void> speak(String text, String languageTag) async {
    try {
      await _tts.setLanguage(languageTag);
      await _tts.setVolume(1);
      await _tts.speak(text);
    } catch (_) {
      // no TTS engine / voice on this phone: the alarm and the screen still work
    }
  }

  @override
  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
