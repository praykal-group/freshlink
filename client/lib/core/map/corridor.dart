import 'dart:math' as math;

/// A map tile address (slippy-map / Web Mercator).
class TileId {
  const TileId(this.z, this.x, this.y);
  final int z;
  final int x;
  final int y;

  @override
  bool operator ==(Object other) => other is TileId && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);

  @override
  String toString() => '$z/$x/$y';
}

/// A route point (degrees).
class GeoPoint {
  const GeoPoint(this.lat, this.lng);
  final double lat;
  final double lng;
}

double _tileX(double lng, int z) => (lng + 180) / 360 * (1 << z);

double _tileY(double lat, int z) {
  final r = lat.clamp(-85.0511, 85.0511) * math.pi / 180;
  return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * (1 << z);
}

const _earthKm = 6371.0;

/// Great-circle distance in km.
double haversineKm(GeoPoint a, GeoPoint b) {
  final dLat = (b.lat - a.lat) * math.pi / 180;
  final dLng = (b.lng - a.lng) * math.pi / 180;
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(a.lat * math.pi / 180) * math.cos(b.lat * math.pi / 180) * math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthKm * math.asin(math.sqrt(h));
}

/// Tiles covering a band of [bufferKm] around the route, zoom [minZoom]..[maxZoom], ordered by
/// zoom (coarse first) and then along the route (DA-NFR-01, D-143). The band, not the bounding
/// box of Section 10.5: a 200 km diagonal route's box at zoom 15 is ~29 000 tiles (≈ 430 MB),
/// far over the 60 MB cap, while the band is what the driver can actually see. Routes carry no
/// road geometry (the optimiser works on stop-to-stop distances), so the band follows the straight
/// stop-to-stop legs; turn-by-turn is the Google Maps hand-off (D-12).
List<TileId> corridorTiles(List<GeoPoint> route, {double bufferKm = 2, int minZoom = 10, int maxZoom = 15}) {
  if (route.isEmpty) return const [];
  final out = <TileId>[];
  for (var z = minZoom; z <= maxZoom; z++) {
    final seen = <TileId>{};
    void cover(GeoPoint p) {
      // the buffer as tile offsets at this latitude (1 deg lat ≈ 111 km)
      final dLat = bufferKm / 111.0;
      final dLng = bufferKm / (111.0 * math.cos(p.lat * math.pi / 180).abs().clamp(0.01, 1.0));
      final x0 = _tileX(p.lng - dLng, z).floor(), x1 = _tileX(p.lng + dLng, z).floor();
      final y0 = _tileY(p.lat + dLat, z).floor(), y1 = _tileY(p.lat - dLat, z).floor();
      final max = (1 << z) - 1;
      for (var x = x0; x <= x1; x++) {
        for (var y = y0; y <= y1; y++) {
          final t = TileId(z, x.clamp(0, max), y.clamp(0, max));
          if (seen.add(t)) out.add(t);
        }
      }
    }

    // Sample each segment at most every buffer/2 km so the band has no gaps between far points.
    final stepKm = math.max(bufferKm / 2, 0.25);
    cover(route.first);
    for (var i = 1; i < route.length; i++) {
      final a = route[i - 1], b = route[i];
      final n = math.max(1, (haversineKm(a, b) / stepKm).ceil());
      for (var k = 1; k <= n; k++) {
        final f = k / n;
        cover(GeoPoint(a.lat + (b.lat - a.lat) * f, a.lng + (b.lng - a.lng) * f));
      }
    }
  }
  return out;
}
