import 'package:speech_to_text/speech_to_text.dart';

/// Voice input for numeric fields (FO-NFR, Section 13.3 mic icon): "twelve point five",
/// "12.5", "बारह दशमलव पाँच" are rare in practice — recognisers return digits for numbers, often
/// with Devanagari digits or a spoken decimal word. This turns the transcript into a number.
const _devanagari = {'०': '0', '१': '1', '२': '2', '३': '3', '४': '4', '५': '5', '६': '6', '७': '7', '८': '8', '९': '9'};
const _decimalWords = ['point', 'dot', 'दशमलव', 'पॉइंट', 'पॉईंट', 'बिंदु', 'पूर्णांक'];
const _minusWords = ['minus', 'negative', 'माइनस', 'उणे', 'ऋण'];

num? parseSpokenNumber(String transcript) {
  var t = transcript.toLowerCase().trim();
  if (t.isEmpty) return null;
  _devanagari.forEach((k, v) => t = t.replaceAll(k, v));
  for (final w in _decimalWords) {
    t = t.replaceAll(RegExp(r'\s*' + RegExp.escape(w) + r'\s*'), '.');
  }
  var negative = false;
  for (final w in _minusWords) {
    if (t.contains(w)) {
      negative = true;
      t = t.replaceAll(w, ' ');
    }
  }
  t = t.replaceAll(',', '.').replaceAll(RegExp(r'(?<=\d)\s+(?=\d)'), '');
  final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(t);
  if (m == null) return null;
  final n = num.tryParse(m.group(0)!);
  if (n == null) return null;
  return negative && n > 0 ? -n : n;
}

/// Speech recognition for one value. Uses the app language (en-IN, hi-IN, mr-IN).
class VoiceNumberInput {
  final _speech = SpeechToText();
  bool _ready = false;

  Future<bool> init() async {
    if (_ready) return true;
    try {
      _ready = await _speech.initialize();
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  /// Listens once (max 6 s) and returns the number heard, or null.
  Future<num?> listen(String languageCode) async {
    if (!await init()) return null;
    String heard = '';
    await _speech.listen(
      onResult: (r) => heard = r.recognizedWords,
      listenOptions: SpeechListenOptions(
        partialResults: false,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        localeId: '$languageCode-IN',
        listenFor: const Duration(seconds: 6),
        pauseFor: const Duration(seconds: 2),
      ),
    );
    for (var i = 0; i < 40 && _speech.isListening; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return parseSpokenNumber(heard);
  }
}
