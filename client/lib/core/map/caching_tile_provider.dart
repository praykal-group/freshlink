import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

import 'corridor.dart';

/// Disk store for map tiles (DA-NFR-01): `<dir>/<z>/<x>/<y>.tile`, capped at [maxBytes]. Over
/// the cap the least recently written tiles are evicted (a new trip's corridor replaces the old).
class TileStore {
  TileStore(this.dir, {this.maxBytes = 60 * 1024 * 1024});

  final Directory dir;
  final int maxBytes;
  int? _size;

  File _file(TileId t) => File('${dir.path}/${t.z}/${t.x}/${t.y}.tile');

  Future<Uint8List?> read(TileId t) async {
    final f = _file(t);
    try {
      return await f.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  Future<bool> has(TileId t) => _file(t).exists();

  Future<void> write(TileId t, Uint8List bytes) async {
    final f = _file(t);
    await f.parent.create(recursive: true);
    final old = await f.exists() ? await f.length() : 0;
    await f.writeAsBytes(bytes, flush: true);
    _size = (await sizeBytes()) - old + bytes.length;
    if (_size! > maxBytes) await _evict();
  }

  Future<int> sizeBytes() async {
    if (_size != null) return _size!;
    var total = 0;
    if (await dir.exists()) {
      await for (final e in dir.list(recursive: true)) {
        if (e is File) total += await e.length();
      }
    }
    return _size = total;
  }

  Future<void> _evict() async {
    final files = <(File, DateTime, int)>[];
    await for (final e in dir.list(recursive: true)) {
      if (e is File) files.add((e, await e.lastModified(), await e.length()));
    }
    files.sort((a, b) => a.$2.compareTo(b.$2));
    var total = files.fold<int>(0, (s, f) => s + f.$3);
    // down to 90 % so every write does not evict again
    for (final f in files) {
      if (total <= maxBytes * 0.9) break;
      await f.$1.delete();
      total -= f.$3;
    }
    _size = total;
  }
}

/// Fetches tile bytes from a URL (dio in the app; a fake in tests).
typedef TileFetch = Future<Uint8List> Function(String url);

TileFetch dioTileFetch(String userAgent) {
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 15), headers: {'User-Agent': userAgent}, responseType: ResponseType.bytes));
  return (url) async => Uint8List.fromList((await dio.get<List<int>>(url)).data!);
}

String tileUrl(String template, TileId t) => template.replaceAll('{z}', '${t.z}').replaceAll('{x}', '${t.x}').replaceAll('{y}', '${t.y}');

/// flutter_map tile provider that reads the disk store first and stores what it downloads, so
/// tiles seen once (or prefetched) show without a network. Our own code: no GPL tile-cache package
/// (Section 10.5).
class CachingTileProvider extends TileProvider {
  CachingTileProvider({required this.store, required this.fetch, required this.urlTemplate});

  final TileStore store;
  final TileFetch fetch;
  final String urlTemplate;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) => CachedTileImage(TileId(coordinates.z, coordinates.x, coordinates.y), this);

  /// Cache hit → bytes; miss → download, store, bytes. Throws offline on a miss.
  Future<Uint8List> bytesFor(TileId t) async {
    final hit = await store.read(t);
    if (hit != null && hit.isNotEmpty) return hit;
    final bytes = await fetch(tileUrl(urlTemplate, t));
    await store.write(t, bytes);
    return bytes;
  }
}

@immutable
class CachedTileImage extends ImageProvider<CachedTileImage> {
  const CachedTileImage(this.tile, this.provider);

  final TileId tile;
  final CachingTileProvider provider;

  @override
  Future<CachedTileImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(CachedTileImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await provider.bytesFor(tile);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is CachedTileImage && other.tile == tile && other.provider.urlTemplate == provider.urlTemplate;

  @override
  int get hashCode => Object.hash(tile, provider.urlTemplate);
}

/// Result of a corridor download.
class PrefetchResult {
  const PrefetchResult({required this.planned, required this.downloaded, required this.cached, required this.failed, required this.stoppedAtCap});
  final int planned;
  final int downloaded;
  final int cached;
  final int failed;
  final bool stoppedAtCap;
}

/// Downloads a trip's corridor before departure (Section 10.5: zoom 10–15, 2 km buffer, ≤ 60 MB).
/// Coarse zooms come first, so a cap or a lost connection still leaves an overview. Only for a
/// tile provider whose terms allow bulk download (D-143): the public OpenStreetMap servers forbid it.
Future<PrefetchResult> prefetchCorridor(CachingTileProvider provider, List<TileId> tiles, {int concurrency = 4, int budgetBytes = 60 * 1024 * 1024, void Function(int done, int total)? onProgress}) async {
  var downloaded = 0, cached = 0, failed = 0, done = 0, bytes = 0;
  var stopped = false;
  var next = 0;
  Future<void> worker() async {
    while (!stopped && next < tiles.length) {
      final t = tiles[next++];
      try {
        if (await provider.store.has(t)) {
          cached++;
        } else {
          final b = await provider.fetch(tileUrl(provider.urlTemplate, t));
          if (bytes + b.length > budgetBytes) {
            stopped = true;
            break;
          }
          await provider.store.write(t, b);
          bytes += b.length;
          downloaded++;
        }
      } catch (_) {
        failed++;
      }
      onProgress?.call(++done, tiles.length);
    }
  }

  await Future.wait(List.generate(concurrency, (_) => worker()));
  return PrefetchResult(planned: tiles.length, downloaded: downloaded, cached: cached, failed: failed, stoppedAtCap: stopped);
}
