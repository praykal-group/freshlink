/// One phone GPS fix (DA-FR-10). The JSON matches the server's GPS_POINTS point
/// (`{at, lat, lng, speedKmh?, accuracyM?}`), so journal lines go to the outbox unchanged.
class GpsFix {
  const GpsFix({required this.at, required this.lat, required this.lng, this.speedKmh, this.accuracyM});

  final DateTime at;
  final double lat;
  final double lng;
  final double? speedKmh;
  final double? accuracyM;

  /// Android reports speed in m/s, or a negative value when unknown.
  static double? kmhFromMps(double mps) => mps < 0 || mps.isNaN ? null : mps * 3.6;

  Map<String, dynamic> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'lat': lat,
        'lng': lng,
        // the server accepts 0..200 km/h and 0..10 000 m
        if (speedKmh != null) 'speedKmh': double.parse(speedKmh!.clamp(0, 200).toStringAsFixed(1)),
        if (accuracyM != null) 'accuracyM': double.parse(accuracyM!.clamp(0, 10000).toStringAsFixed(1)),
      };

  static GpsFix? tryParse(Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse('${json['at']}');
    final lat = (json['lat'] as num?)?.toDouble();
    final lng = (json['lng'] as num?)?.toDouble();
    if (at == null || lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) return null;
    return GpsFix(at: at, lat: lat, lng: lng, speedKmh: (json['speedKmh'] as num?)?.toDouble(), accuracyM: (json['accuracyM'] as num?)?.toDouble());
  }
}
