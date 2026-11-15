import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// A finished voice note: AAC in an .m4a container (`audio/mp4`, server limit 5 MB).
class VoiceNote {
  const VoiceNote({required this.path, required this.bytes, required this.seconds});
  final String path;
  final int bytes;
  final int seconds;
}

/// Voice notes for incidents (DA-FR-09, max 60 s). Tests use a fake.
abstract class VoiceRecorder {
  /// False when the microphone permission is refused.
  Future<bool> start();
  Future<VoiceNote?> stop();
  Future<void> cancel();
}

/// 16 kHz mono AAC at 32 kbit/s: 60 s ≈ 240 KB, clear enough for speech.
class RecordVoiceRecorder implements VoiceRecorder {
  final _rec = AudioRecorder();
  DateTime? _started;
  String? _path;

  @override
  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/voice');
    await dir.create(recursive: true);
    _path = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1, bitRate: 32000), path: _path!);
    _started = DateTime.now();
    return true;
  }

  @override
  Future<VoiceNote?> stop() async {
    final path = await _rec.stop();
    final started = _started;
    _started = null;
    if (path == null || started == null) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    return VoiceNote(path: path, bytes: await f.length(), seconds: DateTime.now().difference(started).inSeconds.clamp(1, 60));
  }

  @override
  Future<void> cancel() async {
    await _rec.cancel();
    _started = null;
  }
}
