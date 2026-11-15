/// Hands a downloaded report to the user (Section 10.6 #10): the console downloads it (HTML opens
/// in a new tab), the APK writes it to a temp file and opens the share sheet. The bytes come from an
/// authenticated API call, so a plain link would not work (it carries no JWT).
library;

export 'save_file_native.dart' if (dart.library.js_interop) 'save_file_web.dart';
