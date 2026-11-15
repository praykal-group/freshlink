import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> saveOrShareFile({required String name, required String mime, required String text}) async {
  final blob = web.Blob([utf8.encode(text).toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  if (mime == 'text/html') {
    web.window.open(url, '_blank'); // the compliance report is read in the browser
  } else {
    final a = web.HTMLAnchorElement()
      ..href = url
      ..download = name;
    a.click();
  }
  Future<void>.delayed(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
}
