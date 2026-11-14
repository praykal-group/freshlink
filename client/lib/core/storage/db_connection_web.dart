import 'package:drift/drift.dart';

/// The web console (manager) is online-only and has no offline outbox (Section 10.6), so it never
/// opens the local database.
QueryExecutor openEncryptedDatabase(String hexKey, {String fileName = 'iccms.db'}) =>
    throw UnsupportedError('The local database is not used on the web');
