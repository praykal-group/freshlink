import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Opens the SQLCipher database (D-118) in a background isolate. The key is a 256-bit random hex
/// string from secure storage; `PRAGMA key` must be the first statement on the connection.
QueryExecutor openEncryptedDatabase(String hexKey, {String fileName = 'iccms.db'}) {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    return encryptedFileExecutor(File('${dir.path}/$fileName'), hexKey);
  });
}

/// Also used by tests with a temporary file.
QueryExecutor encryptedFileExecutor(File file, String hexKey) {
  return NativeDatabase.createInBackground(file, setup: (db) => applyKey(db, hexKey));
}

void applyKey(Database db, String hexKey) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hexKey)) throw ArgumentError('database key must be 64 hex characters');
  // Raw 256-bit key (x'..'): no passphrase derivation needed for a random key.
  db.execute("PRAGMA key = \"x'$hexKey'\";");
  // Fails here (not later on a random query) when the key is wrong or SQLCipher is missing.
  final cipher = db.select('PRAGMA cipher_version;');
  if (cipher.isEmpty) throw StateError('SQLCipher is not available: refusing to store data unencrypted');
  db.select('SELECT count(*) FROM sqlite_master;');
}
