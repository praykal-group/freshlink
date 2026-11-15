DateTime? date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
double? num0(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
Map<String, dynamic> map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> maps(Object? v) => [for (final x in (v as List? ?? const [])) map(x)];

/// Local name (EN / HI / MR) of a product or anything with name / nameHi / nameMr.
String localName(Map<String, dynamic>? p, String lang) {
  if (p == null) return '';
  final local = switch (lang) { 'hi' => p['nameHi'], 'mr' => p['nameMr'], _ => null };
  return (local as String?)?.isNotEmpty == true ? local! : (p['name'] as String? ?? p['code'] as String? ?? '');
}

/// Section 10.6 #1.
class Kpis {
  const Kpis({required this.activeTrips, required this.openCriticalAlerts, required this.atRiskBatches, required this.deliveriesToday, required this.spoilageAvoidedKg});
  final int activeTrips;
  final int openCriticalAlerts;
  final int atRiskBatches;
  final int deliveriesToday;
  final double spoilageAvoidedKg;

  factory Kpis.fromJson(Map<String, dynamic> j) => Kpis(
        activeTrips: (j['activeTrips'] as num? ?? 0).toInt(),
        openCriticalAlerts: (j['openCriticalAlerts'] as num? ?? 0).toInt(),
        atRiskBatches: (j['atRiskBatches'] as num? ?? 0).toInt(),
        deliveriesToday: (j['deliveriesToday'] as num? ?? 0).toInt(),
        spoilageAvoidedKg: num0(j['spoilageAvoidedKg']) ?? 0,
      );
}

class VehiclePosition {
  const VehiclePosition({required this.vehicleId, required this.regNo, this.tripId, this.tripCode, this.driverName, this.lat, this.lng, this.tempC, this.at});
  final String vehicleId;
  final String regNo;
  final String? tripId;
  final String? tripCode;
  final String? driverName;
  final double? lat;
  final double? lng;
  final double? tempC;
  final DateTime? at;

  bool get located => lat != null && lng != null;

  factory VehiclePosition.fromJson(Map<String, dynamic> j) => VehiclePosition(
        vehicleId: '${j['vehicleId']}',
        regNo: j['regNo'] as String? ?? '',
        tripId: j['tripId'] as String?,
        tripCode: j['tripCode'] as String?,
        driverName: j['driverName'] as String?,
        lat: num0(j['lat']),
        lng: num0(j['lng']),
        tempC: num0(j['tempC']),
        at: date(j['at']),
      );

  /// A live `vehicle.position` event moves the marker (other fields kept).
  VehiclePosition moved(Map<String, dynamic> e) => VehiclePosition(
        vehicleId: vehicleId, regNo: regNo, tripId: tripId, tripCode: tripCode, driverName: driverName,
        lat: num0(e['lat']) ?? lat, lng: num0(e['lng']) ?? lng, tempC: num0(e['tempC']) ?? tempC, at: date(e['at'] ?? e['ts']) ?? at,
      );
}

class ControlSummary {
  const ControlSummary({required this.kpis, required this.vehicles, required this.fetchedAt});
  final Kpis kpis;
  final List<VehiclePosition> vehicles;
  final DateTime fetchedAt;

  factory ControlSummary.fromJson(Map<String, dynamic> j) =>
      ControlSummary(kpis: Kpis.fromJson(map(j['kpis'])), vehicles: [for (final v in maps(j['vehicles'])) VehiclePosition.fromJson(v)], fetchedAt: DateTime.now());

  ControlSummary withPosition(Map<String, dynamic> e) => ControlSummary(
        kpis: kpis,
        fetchedAt: fetchedAt,
        vehicles: [for (final v in vehicles) v.vehicleId == '${e['vehicleId']}' ? v.moved(e) : v],
      );
}

/// Trip telemetry for the chart (Section 10.6 #2): mean per window + the cargo's safe band.
class TelemetryPoint {
  const TelemetryPoint(this.at, this.tempC, this.humidityPct);
  final DateTime at;
  final double? tempC;
  final double? humidityPct;
}

class TelemetrySeries {
  const TelemetrySeries({required this.points, this.tempMin, this.tempMax});
  final List<TelemetryPoint> points;
  final double? tempMin;
  final double? tempMax;

  bool outOfBand(TelemetryPoint p) => p.tempC != null && ((tempMin != null && p.tempC! < tempMin!) || (tempMax != null && p.tempC! > tempMax!));
  int get excursions => points.where(outOfBand).length;

  factory TelemetrySeries.fromJson(Map<String, dynamic> j) {
    final band = map(j['band']);
    return TelemetrySeries(
      tempMin: num0(band['tempMin']),
      tempMax: num0(band['tempMax']),
      points: [
        for (final p in maps(j['points']))
          if (date(p['at']) != null) TelemetryPoint(date(p['at'])!, num0(p['temp_c']), num0(p['humidity_pct'])),
      ],
    );
  }
}

/// Section 10.6 #4: one day of a forecast with its range.
class ForecastDay {
  const ForecastDay({required this.day, required this.predictedKg, required this.lowerKg, required this.upperKg, this.modelVersion});
  final DateTime day;
  final double predictedKg;
  final double lowerKg;
  final double upperKg;
  final String? modelVersion;

  factory ForecastDay.fromJson(Map<String, dynamic> j) => ForecastDay(
        day: DateTime.parse('${j['date']}'),
        predictedKg: num0(j['predictedKg']) ?? 0,
        lowerKg: num0(j['lowerKg']) ?? num0(j['predictedKg']) ?? 0,
        upperKg: num0(j['upperKg']) ?? num0(j['predictedKg']) ?? 0,
        modelVersion: j['modelVersion'] as String?,
      );
}

/// Planner need per centre × product (POST /planning/run).
class PlanNeed {
  const PlanNeed({required this.siteCode, required this.productCode, required this.forecastKg, required this.onHandKg, required this.inTransitKg, required this.needKg, required this.shortfallKg});
  final String siteCode;
  final String productCode;
  final double forecastKg;
  final double onHandKg;
  final double inTransitKg;
  final double needKg;
  final double shortfallKg;

  factory PlanNeed.fromJson(Map<String, dynamic> j) => PlanNeed(
        siteCode: '${j['siteCode']}', productCode: '${j['productCode']}', forecastKg: num0(j['forecastKg']) ?? 0, onHandKg: num0(j['onHandKg']) ?? 0,
        inTransitKg: num0(j['inTransitKg']) ?? 0, needKg: num0(j['needKg']) ?? 0, shortfallKg: num0(j['shortfallKg']) ?? 0,
      );
}

/// A page of a cursor-paged list.
class ApiPage {
  const ApiPage(this.items, this.nextCursor);
  final List<Map<String, dynamic>> items;
  final String? nextCursor;

  factory ApiPage.fromJson(Object? j) => j is List ? ApiPage(maps(j), null) : ApiPage(maps(map(j)['items']), map(j)['nextCursor'] as String?);
}

/// Opening hours `{"mon":[["06:00","20:00"]], ...}` (keys sun..sat, IST) — the buyer editor (W-1).
class OpeningHours {
  OpeningHours(this.days);
  static const keys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  final Map<String, List<(String, String)>> days;

  factory OpeningHours.fromJson(Object? j) {
    final m = map(j);
    return OpeningHours({
      for (final k in keys) k: [for (final r in (m[k] as List? ?? const [])) if (r is List && r.length == 2) ('${r[0]}', '${r[1]}')],
    });
  }

  factory OpeningHours.everyDay(String open, String close) => OpeningHours({for (final k in keys) k: [(open, close)]});

  static final _hm = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  /// The server's rule (buyer-rules.ts): HH:MM, at most 4 ranges a day; a range ending before it
  /// starts runs past midnight (allowed). Stricter here: an empty range (open = close) is a typo.
  /// Returns the first bad day key or null.
  String? invalidDay() {
    for (final e in days.entries) {
      if (e.value.length > 4) return e.key;
      for (final (a, b) in e.value) {
        if (!_hm.hasMatch(a) || !_hm.hasMatch(b) || a == b) return e.key;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {for (final e in days.entries) if (e.value.isNotEmpty) e.key: [for (final (a, b) in e.value) [a, b]]};
}
