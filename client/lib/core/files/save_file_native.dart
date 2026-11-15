import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> saveOrShareFile({required String name, required String mime, required String text}) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/reports');
  await dir.create(recursive: true);
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(utf8.encode(text), flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: mime)], subject: name));
}
