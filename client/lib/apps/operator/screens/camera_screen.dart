import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/media/photo_compress.dart';
import '../../../core/theme/app_spacing.dart';

/// One captured photo: the compressed copy that is uploaded and the full-resolution original kept
/// on the phone until the batch is graded (FO-NFR-04).
class CapturedPhoto {
  const CapturedPhoto({required this.path, required this.originalPath, required this.sizeBytes, required this.width, required this.height, required this.capturedAt});
  final String path;
  final String originalPath;
  final int sizeBytes;
  final int width;
  final int height;
  final DateTime capturedAt;
}

/// Guided capture (FO-FR-06): the on-screen frame + an instruction for the view (top / side /
/// close-up). Returns the compressed photo.
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key, required this.title, required this.instruction, required this.fileStem});
  final String title;
  final String instruction;
  final String fileStem;

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.where((c) => c.lensDirection == CameraLensDirection.back).firstOrNull ?? cameras.first;
      final c = CameraController(back, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await c.initialize();
      if (!mounted) return c.dispose();
      setState(() => _controller = c);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    try {
      final shot = await c.takePicture();
      final bytes = await shot.readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      final small = await compressPhoto(bytes, decoded.width, decoded.height);
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/photos');
      await dir.create(recursive: true);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final original = File('${dir.path}/${widget.fileStem}_$stamp.orig.jpg');
      await File(shot.path).copy(original.path);
      final out = File('${dir.path}/${widget.fileStem}_$stamp.jpg');
      await out.writeAsBytes(small.bytes, flush: true);
      if (!mounted) return;
      Navigator.pop(
        context,
        CapturedPhoto(path: out.path, originalPath: original.path, sizeBytes: small.bytes.lengthInBytes, width: small.width, height: small.height, capturedAt: DateTime.now()),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.title), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: Text('${l.cameraUnavailable}\n$_error', style: const TextStyle(color: Colors.white), textAlign: TextAlign.center)))
          : c == null
              ? const Center(child: CircularProgressIndicator())
              : Stack(fit: StackFit.expand, children: [
                  Center(child: CameraPreview(c)),
                  // Guide frame (FO-FR-06)
                  Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.82,
                      heightFactor: 0.55,
                      child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(AppRadius.card))),
                    ),
                  ),
                  Positioned(
                    left: AppSpacing.lg,
                    right: AppSpacing.lg,
                    top: AppSpacing.lg,
                    child: Text(widget.instruction, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 6)])),
                  ),
                  Positioned(
                    bottom: AppSpacing.xxl,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Semantics(
                        button: true,
                        label: widget.title,
                        child: GestureDetector(
                          onTap: _capture,
                          child: Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 5)),
                            child: Center(child: _busy ? const CircularProgressIndicator(color: Colors.white) : Container(width: 64, height: 64, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white))),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
    );
  }
}
