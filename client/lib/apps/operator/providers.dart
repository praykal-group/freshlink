import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/printing/label_printer.dart';
import '../../core/providers.dart';
import '../../core/tags/nfc_tag_reader.dart';
import '../../core/tags/qr_tag_reader.dart';
import '../../core/tags/tag_reader.dart';
import '../../core/tags/wedge_tag_reader.dart';
import '../../core/voice/voice_number.dart';
import 'data/models.dart';
import 'data/operator_repository.dart';
import 'screens/camera_screen.dart';

final operatorRepositoryProvider = Provider<OperatorRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final outbox = ref.watch(outboxProvider);
  if (db == null || outbox == null) throw StateError('The operator app needs the local database');
  return OperatorRepository(api: ref.watch(apiClientProvider), db: db, outbox: outbox);
});

final mastersProvider = FutureProvider<Masters>((ref) => ref.watch(operatorRepositoryProvider).masters());

final summaryProvider = FutureProvider.autoDispose<OperatorSummary>((ref) => ref.watch(operatorRepositoryProvider).summary());

final operatorTripsProvider = FutureProvider.autoDispose<List<OperatorTrip>>((ref) => ref.watch(operatorRepositoryProvider).trips());

/// Readers in the order offered (FO-FR-05). Overridden in tests.
final tagReadersProvider = Provider<Map<TagKind, TagReader>>((_) => const {
      TagKind.nfc: NfcTagReader(),
      TagKind.qr: QrTagReader(),
      TagKind.uhf: WedgeTagReader(),
    });

/// Guided photo capture (FO-FR-06): opens the camera screen. Tests replace it with stored photos.
typedef PhotoCapture = Future<CapturedPhoto?> Function(BuildContext context, {required String title, required String instruction, required String fileStem});

final photoCaptureProvider = Provider<PhotoCapture>((_) => (context, {required title, required instruction, required fileStem}) =>
    Navigator.of(context).push<CapturedPhoto>(MaterialPageRoute(builder: (_) => CameraCaptureScreen(title: title, instruction: instruction, fileStem: fileStem))));

final voiceInputProvider = Provider<VoiceNumberInput>((_) => VoiceNumberInput());

final labelPrinterProvider = Provider<BluetoothLabelPrinter>((_) => const BluetoothLabelPrinter());

const _printerKey = 'operator.printerMac';

class PrinterController extends AsyncNotifier<String?> {
  @override
  Future<String?> build() => ref.read(databaseProvider)!.kvGet(_printerKey);

  Future<void> select(String mac) async {
    await ref.read(databaseProvider)!.kvSet(_printerKey, mac);
    state = AsyncData(mac);
  }
}

final printerProvider = AsyncNotifierProvider<PrinterController, String?>(PrinterController.new);

/// After every sync pass: grade the batches registered offline whose data is now on the server,
/// then refresh what the screens show (Section 10.4 "the grade arrives later").
final gradeQueueWorkerProvider = Provider<void>((ref) {
  final scheduler = ref.watch(syncSchedulerProvider);
  final repo = ref.watch(operatorRepositoryProvider);
  if (scheduler == null) return;
  var busy = false;
  final sub = scheduler.reports.listen((report) async {
    if (busy) return;
    busy = true;
    try {
      final graded = await repo.processPendingGrades();
      if (report.applied > 0 || graded.isNotEmpty) {
        ref.invalidate(summaryProvider);
        ref.invalidate(batchRefreshProvider);
      }
    } catch (_) {
      // Next pass retries.
    } finally {
      busy = false;
    }
  });
  ref.onDispose(sub.cancel);
});

/// The wizard draft shown as "Continue the batch you started" on the home screen.
final operatorDraftProvider = FutureProvider<WizardDraft?>((ref) => ref.watch(databaseProvider)!.loadDraft());

/// Bumped when batch data changed (sync applied, grade arrived): lists re-read.
final batchRefreshProvider = Provider<int>((ref) => DateTime.now().millisecondsSinceEpoch);
