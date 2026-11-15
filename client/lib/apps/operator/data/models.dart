/// Operator-app models built from the API JSON. Prisma decimals arrive as strings, so numbers go
/// through [_num].
double? _num(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
double _numOr(Object? v, double fallback) => _num(v) ?? fallback;

class Product {
  const Product({
    required this.id, required this.code, required this.name, required this.nameHi, required this.nameMr, required this.category,
    required this.isClimacteric, required this.safeTempMin, required this.safeTempMax,
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String,
        code: j['code'] as String,
        name: j['name'] as String,
        nameHi: j['nameHi'] as String? ?? j['name'] as String,
        nameMr: j['nameMr'] as String? ?? j['name'] as String,
        category: j['category'] as String,
        isClimacteric: j['isClimacteric'] == true,
        safeTempMin: _numOr(j['safeTempMin'], 0),
        safeTempMax: _numOr(j['safeTempMax'], 10),
      );

  final String id;
  final String code;
  final String name;
  final String nameHi;
  final String nameMr;

  /// FISH | PRODUCE
  final String category;
  final bool isClimacteric;
  final double safeTempMin;
  final double safeTempMax;

  bool get isFish => category == 'FISH';

  String localName(String lang) => switch (lang) {
        'hi' => nameHi,
        'mr' => nameMr,
        _ => name,
      };
}

class Site {
  const Site({required this.id, required this.code, required this.name, required this.type});
  factory Site.fromJson(Map<String, dynamic> j) => Site(id: j['id'] as String, code: j['code'] as String, name: j['name'] as String, type: j['type'] as String);
  final String id;
  final String code;
  final String name;
  final String type;
}

class StorageUnit {
  const StorageUnit({required this.id, required this.siteId, required this.code, required this.type, required this.tempMin, required this.tempMax, required this.capacityKg, required this.usedKg});
  factory StorageUnit.fromJson(Map<String, dynamic> j) => StorageUnit(
        id: j['id'] as String,
        siteId: j['siteId'] as String,
        code: j['code'] as String,
        type: j['type'] as String,
        tempMin: _numOr(j['tempMin'], -30),
        tempMax: _numOr(j['tempMax'], 30),
        capacityKg: _numOr(j['capacityKg'], 0),
        usedKg: _numOr(j['usedKg'], 0),
      );
  final String id;
  final String siteId;
  final String code;

  /// BLAST_CHILLER | RIPENING_CHAMBER | COLD_ROOM
  final String type;
  final double tempMin;
  final double tempMax;
  final double capacityKg;
  final double usedKg;

  double get freeKg => capacityKg - usedKg;
}

class Masters {
  const Masters({required this.products, required this.sites, required this.units, required this.fetchedAt, this.fromCache = false});
  factory Masters.fromJson(Map<String, dynamic> j, {required DateTime fetchedAt, bool fromCache = false}) => Masters(
        products: [for (final p in (j['products'] as List? ?? const [])) Product.fromJson(Map<String, dynamic>.from(p as Map))],
        sites: [for (final s in (j['sites'] as List? ?? const [])) Site.fromJson(Map<String, dynamic>.from(s as Map))],
        units: [for (final u in (j['storageUnits'] as List? ?? const [])) StorageUnit.fromJson(Map<String, dynamic>.from(u as Map))],
        fetchedAt: fetchedAt,
        fromCache: fromCache,
      );
  final List<Product> products;
  final List<Site> sites;
  final List<StorageUnit> units;
  final DateTime fetchedAt;
  final bool fromCache;

  Product? product(String id) => products.where((p) => p.id == id).firstOrNull;
  List<Product> byCategory(String category) => products.where((p) => p.category == category).toList();
}

/// A batch in lists and details. `pending` = created on this phone and not yet on the server.
class BatchItem {
  const BatchItem({
    required this.id, this.code, required this.productId, required this.status, required this.weightKg, this.grade, required this.caughtOrHarvestedAt,
    required this.createdAt, this.remainingShelfLifeH, this.storageUnitCode, this.pending = false, this.productName,
  });

  factory BatchItem.fromJson(Map<String, dynamic> j, {bool pending = false}) => BatchItem(
        id: j['id'] as String,
        code: j['code'] as String?,
        productId: j['productId'] as String,
        status: j['status'] as String? ?? 'REGISTERED',
        weightKg: _numOr(j['weightKg'], 0),
        grade: j['currentGrade'] as String?,
        caughtOrHarvestedAt: DateTime.parse(j['caughtOrHarvestedAt'] as String),
        createdAt: DateTime.parse((j['createdAt'] ?? j['capturedAt']) as String),
        remainingShelfLifeH: _num(j['remainingShelfLifeH']),
        storageUnitCode: (j['storageUnit'] as Map?)?['code'] as String?,
        productName: (j['product'] as Map?)?['name'] as String?,
        pending: pending,
      );

  final String id;
  final String? code;
  final String productId;
  final String status;
  final double weightKg;
  final String? grade;
  final DateTime caughtOrHarvestedAt;
  final DateTime createdAt;
  final double? remainingShelfLifeH;
  final String? storageUnitCode;
  final String? productName;
  final bool pending;

  /// FO-FR-13: direct edits only within 30 minutes of creation.
  bool editableAt(DateTime now) => now.difference(createdAt) <= const Duration(minutes: 30);

  String get displayCode => code ?? '${id.substring(0, 8).toUpperCase()}…';
}

class GradeResult {
  const GradeResult({required this.id, required this.grade, required this.confidence, required this.defects, this.storagePath});
  factory GradeResult.fromJson(Map<String, dynamic> j) => GradeResult(
        id: j['id'] as String,
        grade: j['grade'] as String,
        confidence: _numOr(j['confidence'], 0),
        defects: [for (final d in (j['defects'] as List? ?? const [])) Map<String, dynamic>.from(d as Map)],
        storagePath: j['storagePath'] == null ? null : StoragePath.fromJson(Map<String, dynamic>.from(j['storagePath'] as Map)),
      );
  final String id;
  final String grade;
  final double confidence;
  final List<Map<String, dynamic>> defects;
  final StoragePath? storagePath;
}

class UnitOption {
  const UnitOption({required this.id, required this.code, required this.type, required this.freeKg});
  factory UnitOption.fromJson(Map<String, dynamic> j) => UnitOption(id: j['id'] as String, code: j['code'] as String, type: j['type'] as String, freeKg: _numOr(j['freeKg'], 0));
  final String id;
  final String code;
  final String type;
  final double freeKg;
}

/// `GET /batches/:id/storage-path` (FO-FR-08), or computed on the phone while offline.
class StoragePath {
  const StoragePath({required this.path, required this.sellFirst, this.recommended, this.alternatives = const [], this.offline = false});
  factory StoragePath.fromJson(Map<String, dynamic> j) => StoragePath(
        path: j['path'] as String,
        sellFirst: j['sellFirst'] == true,
        recommended: j['recommendedUnit'] == null ? null : UnitOption.fromJson(Map<String, dynamic>.from(j['recommendedUnit'] as Map)),
        alternatives: [for (final u in (j['alternatives'] as List? ?? const [])) UnitOption.fromJson(Map<String, dynamic>.from(u as Map))],
      );

  /// BLAST_CHILLER | RIPENING_CHAMBER | COLD_ROOM
  final String path;
  final bool sellFirst;
  final UnitOption? recommended;
  final List<UnitOption> alternatives;
  final bool offline;
}

/// Same rule as the server (storage-rules.ts, SYN-10/20) for the offline preview.
StoragePath localStoragePath(Product p, String? grade, List<StorageUnit> unitsAtSite, double weightKg) {
  final path = grade == 'C' ? 'COLD_ROOM' : (p.isFish || !p.isClimacteric ? 'BLAST_CHILLER' : 'RIPENING_CHAMBER');
  final fits = unitsAtSite
      .where((u) => u.type == path && u.freeKg >= weightKg && u.tempMin <= p.safeTempMax && u.tempMax >= p.safeTempMin)
      .toList()
    ..sort((a, b) => b.freeKg.compareTo(a.freeKg));
  final opts = fits.map((u) => UnitOption(id: u.id, code: u.code, type: u.type, freeKg: u.freeKg)).toList();
  return StoragePath(path: path, sellFirst: grade == 'C', recommended: opts.firstOrNull, alternatives: opts.skip(1).take(3).toList(), offline: true);
}

class OperatorSummary {
  const OperatorSummary({required this.siteName, required this.registered, required this.graded, required this.stored, required this.dispatched});
  factory OperatorSummary.fromJson(Map<String, dynamic> j) => OperatorSummary(
        siteName: (j['site'] as Map?)?['name'] as String? ?? '',
        registered: (j['registered'] as num?)?.toInt() ?? 0,
        graded: (j['graded'] as num?)?.toInt() ?? 0,
        stored: (j['stored'] as num?)?.toInt() ?? 0,
        dispatched: (j['dispatched'] as num?)?.toInt() ?? 0,
      );
  final String siteName;
  final int registered;
  final int graded;
  final int stored;
  final int dispatched;

  Map<String, dynamic> toJson() => {'site': {'name': siteName}, 'registered': registered, 'graded': graded, 'stored': stored, 'dispatched': dispatched};
}

class TripBatchRef {
  const TripBatchRef({required this.id, required this.code, required this.weightKg});
  final String id;
  final String code;
  final double weightKg;
}

class OperatorTrip {
  const OperatorTrip({required this.id, required this.code, required this.status, required this.plannedStart, required this.vehicleRegNo, this.driverName, required this.allocated, required this.loadedBatchIds});
  factory OperatorTrip.fromJson(Map<String, dynamic> j) => OperatorTrip(
        id: j['id'] as String,
        code: j['code'] as String,
        status: j['status'] as String,
        plannedStart: DateTime.parse(j['plannedStart'] as String),
        vehicleRegNo: (j['vehicle'] as Map)['regNo'] as String,
        driverName: j['driverName'] as String?,
        allocated: [
          for (final a in (j['allocated'] as List? ?? const []))
            TripBatchRef(id: (a as Map)['id'] as String, code: a['code'] as String, weightKg: _numOr(a['weightKg'], 0)),
        ],
        loadedBatchIds: [for (final b in (j['loadedBatchIds'] as List? ?? const [])) b as String],
      );
  final String id;
  final String code;
  final String status;
  final DateTime plannedStart;
  final String vehicleRegNo;
  final String? driverName;
  final List<TripBatchRef> allocated;
  final List<String> loadedBatchIds;
}
