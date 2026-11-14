import 'dart:math';

import 'secure_store.dart';

/// 256-bit database key, generated on first run and kept in secure storage (Section 10.2).
Future<String> loadOrCreateDbKey(SecureStore store, {Random? random}) async {
  final existing = await store.read(SecureKeys.dbKey);
  if (existing != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(existing)) return existing;
  final r = random ?? Random.secure();
  final key = List.generate(32, (_) => r.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  await store.write(SecureKeys.dbKey, key);
  return key;
}
