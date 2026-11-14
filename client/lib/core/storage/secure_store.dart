import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small secrets (DB key, device id, Supabase session): Android Keystore-backed storage
/// (Section 14). An interface so tests and the web build can swap it.
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureStore implements SecureStore {
  FlutterSecureStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);

  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemorySecureStore implements SecureStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class SecureKeys {
  const SecureKeys._();
  static const dbKey = 'iccms.db_key';
  static const deviceId = 'iccms.device_id';
  static const supabaseSession = 'iccms.supabase_session';
}
