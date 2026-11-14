import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iccms/core/storage/database.dart';
import 'package:iccms/core/storage/db_connection_native.dart';
import 'package:iccms/core/storage/db_key.dart';
import 'package:iccms/core/storage/secure_store.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('iccms_db_'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('the database file is encrypted with SQLCipher and only opens with its key', () async {
    final store = MemorySecureStore();
    final key = await loadOrCreateDbKey(store);
    expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(await loadOrCreateDbKey(store), key, reason: 'the key is created once and reused');

    final file = File('${dir.path}/test.db');
    final db = AppDatabase(encryptedFileExecutor(file, key));
    await db.kvSet('marker', 'cold-chain-plaintext-marker');
    expect(await db.kvGet('marker'), 'cold-chain-plaintext-marker');
    await db.close();

    // Nothing readable on disk: no SQLite header, no plaintext value.
    final bytes = await file.readAsBytes();
    expect(String.fromCharCodes(bytes.take(15)), isNot('SQLite format 3'));
    expect(String.fromCharCodes(bytes).contains('cold-chain-plaintext-marker'), isFalse);

    // Same key reopens; another key is refused at open time.
    final again = AppDatabase(encryptedFileExecutor(file, key));
    expect(await again.kvGet('marker'), 'cold-chain-plaintext-marker');
    await again.close();
    final wrong = AppDatabase(encryptedFileExecutor(file, 'ab' * 32));
    await expectLater(wrong.kvGet('marker'), throwsA(anything));
    await wrong.close().catchError((_) {});
  });
}
