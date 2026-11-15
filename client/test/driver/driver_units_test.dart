import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iccms/apps/driver/data/models.dart';
import 'package:iccms/core/alarm/alert_alarm.dart';
import 'package:iccms/core/location/gps_fix.dart';
import 'package:iccms/core/location/gps_journal.dart';
import 'package:iccms/core/location/speed_lock.dart';
import 'package:iccms/core/map/caching_tile_provider.dart';
import 'package:iccms/core/map/corridor.dart';

GpsFix fix(int s, {double? kmh, double? acc, double lat = 19.88, double lng = 75.34}) =>
    GpsFix(at: DateTime.utc(2026, 11, 15, 6).add(Duration(seconds: s)), lat: lat, lng: lng, speedKmh: kmh, accuracyM: acc);

class _Rec implements AlarmOutput {
  final log = <String>[];
  @override
  Future<void> startLoop(String title, String body) async => log.add('loop');
  @override
  Future<void> stopLoop() async => log.add('stopLoop');
  @override
  Future<void> ring(String title, String body) async => log.add('ring');
  @override
  Future<void> speak(String text, String languageTag) async => log.add('speak:$languageTag');
  @override
  Future<void> stopSpeaking() async => log.add('stopSpeaking');
}

TripBatch batch(String id, {double kg = 120, List<String> tags = const ['04A1B2']}) => TripBatch(id: id, code: 'FSH-$id', weightKg: kg, status: 'IN_TRANSIT', tagUids: tags);

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('iccms_m12_'));
  tearDown(() async => tmp.delete(recursive: true));

  group('GPS journal (DA-FR-10, DA-NFR-01 no data loss)', () {
    test('fixes appended by the service are drained once, oldest first', () async {
      final j = GpsJournal(tmp);
      await j.append(fix(60));
      await j.append(fix(30));
      final got = <GpsFix>[];
      expect(await j.drain((f) async => got.addAll(f)), 2);
      expect(got.map((f) => f.at.second), [30, 0], reason: '06:00:30 then 06:01:00');
      expect(await j.drain((f) async => fail('nothing left')), 0);
    });

    test('a fix appended during a drain goes to the next drain, not lost or read twice', () async {
      final j = GpsJournal(tmp);
      await j.append(fix(0));
      final first = <GpsFix>[];
      await j.drain((f) async {
        first.addAll(f);
        await j.append(fix(30)); // the service keeps writing meanwhile
      });
      final second = <GpsFix>[];
      await j.drain((f) async => second.addAll(f));
      expect([first.length, second.length], [1, 1]);
      expect(second.single.at, fix(30).at);
    });

    test('a failed store keeps the points; a line cut by a killed process is skipped', () async {
      final j = GpsJournal(tmp);
      await j.append(fix(0));
      await File('${tmp.path}/gps.jsonl').writeAsString('{"at":"2026-11-15T06:00', mode: FileMode.append);
      await expectLater(j.drain((_) async => throw StateError('disk full')), throwsStateError);
      final got = <GpsFix>[];
      expect(await j.drain((f) async => got.addAll(f)), 1);
      expect(got.single.at, fix(0).at);
    });

    test('JSON matches the server GPS_POINTS point and clamps to its ranges', () {
      expect(fix(0, kmh: 250, acc: 12.345).toJson(), {'at': '2026-11-15T06:00:00.000Z', 'lat': 19.88, 'lng': 75.34, 'speedKmh': 200.0, 'accuracyM': 12.3});
      expect(GpsFix.kmhFromMps(-1), isNull);
      expect(GpsFix.kmhFromMps(10), closeTo(36, 1e-9));
      expect(GpsFix.tryParse({'at': 'x', 'lat': 1, 'lng': 1}), isNull);
      expect(GpsFix.tryParse({'at': '2026-11-15T06:00:00Z', 'lat': 91, 'lng': 1}), isNull);
    });
  });

  group('speed lock (DA-NFR-08)', () {
    test('locks above 10 km/h; unlocks only after 8 s at or below it', () {
      final l = SpeedLock();
      expect(l.update(fix(0, kmh: 9)), isFalse);
      expect(l.update(fix(10, kmh: 25)), isTrue);
      expect(l.update(fix(20, kmh: 4)), isTrue, reason: 'a stop at a junction');
      expect(l.update(fix(25, kmh: 12)), isTrue);
      expect(l.update(fix(30, kmh: 0)), isTrue);
      expect(l.update(fix(37, kmh: 0)), isTrue, reason: '7 s slow');
      expect(l.update(fix(38, kmh: 0)), isFalse, reason: '8 s slow → unlocked');
    });

    test('an inaccurate or speedless fix never unlocks; reset always does', () {
      final l = SpeedLock()..update(fix(0, kmh: 40));
      expect(l.update(fix(20, kmh: 0, acc: 120)), isTrue);
      expect(l.update(fix(40)), isTrue, reason: 'no speed: no change');
      expect(l.update(fix(60, kmh: 0, acc: 120)), isTrue);
      l.reset();
      expect(l.locked, isFalse);
    });
  });

  group('map corridor (DA-NFR-01: zoom 10–15, 2 km buffer, ≤ 60 MB)', () {
    // Paithan dock → Sambhajinagar DC → Jalna (≈ 110 km)
    const route = [GeoPoint(19.4760, 75.3830), GeoPoint(19.8762, 75.3433), GeoPoint(19.8347, 75.8816)];

    test('coarse zooms first, every zoom covers every stop', () {
      final tiles = corridorTiles(route);
      expect(tiles.first.z, 10);
      expect(tiles.last.z, 15);
      for (var i = 1; i < tiles.length; i++) {
        expect(tiles[i].z >= tiles[i - 1].z, isTrue);
      }
      expect(tiles.toSet().length, tiles.length, reason: 'no duplicates');
      for (final z in [10, 15]) {
        for (final p in route) {
          final x = ((p.lng + 180) / 360 * (1 << z)).floor();
          expect(tiles.any((t) => t.z == z && t.x == x), isTrue);
        }
      }
    });

    test('the band is far smaller than the bounding box and fits the 60 MB cap', () {
      final z15 = corridorTiles(route).where((t) => t.z == 15).toList();
      final xs = z15.map((t) => t.x), ys = z15.map((t) => t.y);
      final box = (xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b) + 1) * (ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b) + 1);
      expect(z15.length, lessThan(box ~/ 5));
      // ~15 KB per OSM tile is typical (not measured here: no tile server allows a bulk test)
      expect(corridorTiles(route).length * 15 * 1024, lessThan(60 * 1024 * 1024));
    });

    test('haversine: Paithan → Sambhajinagar ≈ 44.7 km', () {
      expect(haversineKm(route[0], route[1]), closeTo(44.7, 0.5));
    });
  });

  group('tile cache', () {
    Uint8List bytes(int n) => Uint8List.fromList(List.filled(n, 7));

    test('hit after the first download; offline miss throws; a hit needs no network', () async {
      var calls = 0;
      var online = true;
      final p = CachingTileProvider(
        store: TileStore(Directory('${tmp.path}/tiles')),
        urlTemplate: 'https://tiles.test/{z}/{x}/{y}.png',
        fetch: (url) async {
          calls++;
          if (!online) throw const SocketException('offline');
          expect(url, 'https://tiles.test/12/2905/1832.png');
          return bytes(100);
        },
      );
      const t = TileId(12, 2905, 1832);
      expect((await p.bytesFor(t)).length, 100);
      online = false;
      expect((await p.bytesFor(t)).length, 100);
      expect(calls, 1);
      await expectLater(p.bytesFor(const TileId(12, 1, 1)), throwsA(isA<SocketException>()));
    });

    test('the store evicts the oldest tiles above its cap', () async {
      final s = TileStore(Directory('${tmp.path}/tiles'), maxBytes: 1000);
      for (var i = 0; i < 6; i++) {
        await s.write(TileId(10, i, 0), bytes(300));
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
      expect(await s.sizeBytes(), lessThanOrEqualTo(1000));
      expect(await s.has(const TileId(10, 5, 0)), isTrue, reason: 'the newest stays');
      expect(await s.has(const TileId(10, 0, 0)), isFalse, reason: 'the oldest went');
    });

    test('prefetch stops at the byte budget and counts what was already cached', () async {
      final p = CachingTileProvider(store: TileStore(Directory('${tmp.path}/tiles')), urlTemplate: '{z}/{x}/{y}', fetch: (_) async => bytes(400));
      await p.store.write(const TileId(10, 0, 0), bytes(400));
      final r = await prefetchCorridor(p, [for (var x = 0; x < 6; x++) TileId(10, x, 0)], concurrency: 1, budgetBytes: 1000);
      expect([r.cached, r.downloaded, r.stoppedAtCap], [1, 2, true]);
    });
  });

  group('alert alarm (DA-FR-06)', () {
    test('loops 2 min, then rings + speaks every 30 s until acknowledged', () {
      fakeAsync((async) {
        final out = _Rec();
        final a = AlertAlarm(out);
        a.start(alertId: 'a1', title: 'T', body: 'B', speech: 'S', languageTag: 'hi-IN');
        async.flushMicrotasks();
        expect(out.log, ['loop', 'speak:hi-IN']);
        async.elapse(const Duration(minutes: 1, seconds: 59));
        expect(out.log, ['loop', 'speak:hi-IN']);
        async.elapse(const Duration(seconds: 1));
        expect(out.log.last, 'stopLoop');
        async.elapse(const Duration(seconds: 60));
        expect(out.log.where((e) => e == 'ring').length, 2);
        a.stop();
        async.flushMicrotasks();
        final n = out.log.length;
        async.elapse(const Duration(minutes: 5));
        expect(out.log.length, n, reason: 'silent after the ack');
        expect(a.activeAlertId, isNull);
      });
    });

    test('the same alert twice does not restart it', () {
      fakeAsync((async) {
        final out = _Rec();
        final a = AlertAlarm(out);
        a.start(alertId: 'a1', title: 'T', body: 'B', speech: 'S', languageTag: 'en-IN');
        async.flushMicrotasks();
        a.start(alertId: 'a1', title: 'T', body: 'B', speech: 'S', languageTag: 'en-IN');
        async.flushMicrotasks();
        expect(out.log.where((e) => e == 'loop').length, 1);
        a.stop();
        async.flushMicrotasks();
      });
    });
  });

  group('PoD rules = server checkOutcome (DA-FR-12)', () {
    test('scan, outcome, kg and reason', () {
      final l = PodLine(batch('b1'));
      expect(l.problem(), 'scan');
      l.scanned = 'ZZZZ';
      expect(l.problem(), 'tag');
      l.scanned = 'FSH-b1'; // the label QR (batch code) also counts
      expect(l.problem(), isNull);
      expect(l.kgForServer, 120);
      l.outcome = 'PARTIAL';
      expect(l.problem(), 'kg');
      l.acceptedKg = 120;
      expect(l.problem(), 'kg', reason: 'partial must be less than the full weight');
      l.acceptedKg = 80;
      expect(l.problem(), 'reason');
      l.reason = '  ';
      expect(l.problem(), 'reason');
      l.reason = 'two crates crushed';
      expect(l.problem(), isNull);
      expect(l.kgForServer, 80);
      l.outcome = 'REJECTED';
      expect(l.kgForServer, 0);
    });
  });

  group('trip model', () {
    final json = {
      'id': 't1', 'code': 'TRP-1', 'status': 'IN_PROGRESS', 'plannedStart': '2026-11-15T01:30:00Z', 'currentRouteVersion': 1,
      'stops': [
        {'id': 's2', 'seq': 2, 'type': 'DIVERSION_DROP', 'lat': 19.8, 'lng': 75.8, 'status': 'PENDING', 'buyer': {'name': 'Jalna Fresh'}, 'batchIds': null},
        {'id': 's0', 'seq': 0, 'type': 'PICKUP', 'lat': 19.4, 'lng': 75.3, 'status': 'COMPLETED', 'site': {'code': 'DEP', 'name': 'Depot'}},
        {'id': 's1', 'seq': 1, 'type': 'DROP', 'lat': 19.87, 'lng': 75.34, 'status': 'COMPLETED', 'site': {'code': 'DC', 'name': 'DC'}, 'batchIds': ['b1'], 'orderId': 'o1'},
      ],
      'batches': [
        {'batchId': 'b1', 'code': 'FSH-b1', 'weightKg': 120, 'status': 'DELIVERED', 'tagUids': ['04A1']},
        {'batchId': 'b2', 'code': 'FSH-b2', 'weightKg': 80, 'status': 'IN_TRANSIT', 'tagUids': []},
      ],
    };

    test('stops in order; next stop skips done ones; an open drop takes any batch still on board', () {
      final t = DriverTrip.fromJson(json);
      expect(t.stops.map((s) => s.id), ['s0', 's1', 's2']);
      expect(t.nextStop!.name, 'Jalna Fresh');
      expect(t.batchesFor(t.nextStop!).map((b) => b.id), ['b2'], reason: 'b1 was delivered');
      expect(t.batchesFor(t.stops[1]).map((b) => b.id), isEmpty);
    });

    test('route proposal: the first stop that changes, old vs new', () {
      final p = RouteProposal.fromRouteJson({
        'accepted': {'stopRows': [{'id': 'a', 'seq': 1, 'type': 'DROP', 'lat': 1, 'lng': 1, 'status': 'PENDING', 'site': {'name': 'Sambhajinagar DC'}}]},
        'pending': {'version': 2, 'reason': 'DIVERSION', 'canDecline': false, 'extraKm': 11.2, 'stopRows': [{'id': 'b', 'seq': 1, 'type': 'DIVERSION_DROP', 'lat': 2, 'lng': 2, 'status': 'PENDING', 'buyer': {'name': 'Jalna Fresh'}}]},
      })!;
      final (o, n) = p.changedStop;
      expect([o!.name, n!.name, p.canDecline, p.extraKm], ['Sambhajinagar DC', 'Jalna Fresh', false, 11.2]);
      expect(RouteProposal.fromRouteJson({'pending': null}), isNull);
    });

    test('cargo: lowest shelf life and out-of-range temperature', () {
      final c = CargoStatus.fromJson({
        'telemetry': {'tempC': 6.4, 'humidityPct': 88, 'ts': '2026-11-15T06:00:00Z'},
        'batches': [
          {'batchId': 'b1', 'code': 'F1', 'product': {'name': 'Rohu', 'safeTempMin': 0, 'safeTempMax': 4}, 'weightKg': 100, 'remainingShelfLifeH': 30.5},
          {'batchId': 'b2', 'code': 'F2', 'product': {'name': 'Banana', 'safeTempMin': 13, 'safeTempMax': 15}, 'weightKg': 50, 'remainingShelfLifeH': 72},
        ],
      });
      expect(c.lowestShelfLifeH, 30.5);
      expect(c.tempOutOfRange, isTrue);
    });
  });
}
