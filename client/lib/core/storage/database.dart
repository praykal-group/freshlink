import 'package:drift/drift.dart';

part 'database.g.dart';

/// Section 10.2 core/storage tables. Cached entities keep the server JSON as text: the API stays the
/// source of truth and the UI reads typed models built from it.

@DataClassName('CachedMaster')
class CachedMasters extends Table {
  /// products | sites | storageUnits | config | bundle
  TextColumn get kind => text()();
  TextColumn get payload => text()();
  TextColumn get etag => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {kind};
}

@DataClassName('CachedTrip')
class CachedTrips extends Table {
  TextColumn get id => text()();
  TextColumn get payload => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CachedRoute')
class CachedRoutes extends Table {
  TextColumn get tripId => text()();
  IntColumn get version => integer()();
  TextColumn get payload => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {tripId, version};
}

@DataClassName('CachedBatch')
class CachedBatches extends Table {
  TextColumn get id => text()();
  TextColumn get payload => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Offline writes waiting for `/sync` (Section 10.2 core/sync).
@DataClassName('OutboxOp')
class OutboxOps extends Table {
  /// Client UUID; the server makes every op idempotent on it (`sync_ops`).
  TextColumn get clientOpId => text()();

  /// BATCH_CREATE, TRIP_EVENT, POD, ... (server SYNC_TYPES).
  TextColumn get type => text()();

  /// Ops on the same entity are sent strictly in capture order (one blocked op holds the rest).
  TextColumn get entityId => text()();
  TextColumn get payload => text()();

  /// JSON array of pending_files ids this op needs uploaded first.
  TextColumn get fileIds => text().withDefault(const Constant('[]'))();
  DateTimeColumn get capturedAt => dateTime()();

  /// pending | attention (permanent failure, shown in the Sync Queue)
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastErrorCode => text().nullable()();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {clientOpId};
}

/// Files to upload (presign → PUT) before the ops that reference them.
@DataClassName('PendingFile')
class PendingFiles extends Table {
  TextColumn get id => text()();
  TextColumn get localPath => text()();

  /// BATCH_IMAGE | POD_SIGNATURE | POD_PHOTO | INCIDENT_PHOTO | VOICE_NOTE
  TextColumn get purpose => text()();
  TextColumn get contentType => text()();
  IntColumn get sizeBytes => integer()();

  /// S3 key once uploaded; ops get it substituted for `{"$file": id}` placeholders.
  TextColumn get remoteKey => text().nullable()();

  /// pending | uploaded | attention
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('KvEntry')
class Kv extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [CachedMasters, CachedTrips, CachedRoutes, CachedBatches, OutboxOps, PendingFiles, Kv])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement('CREATE INDEX outbox_due ON outbox_ops (status, next_attempt_at, captured_at)');
          await customStatement('CREATE INDEX outbox_entity ON outbox_ops (entity_id, captured_at)');
        },
      );

  Future<String?> kvGet(String key) async => (await (select(kv)..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> kvSet(String key, String value) => into(kv).insertOnConflictUpdate(KvCompanion.insert(key: key, value: value));
}
