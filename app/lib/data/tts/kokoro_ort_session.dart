/// Real Kokoro inference via flutter_onnxruntime (the [KokoroSession] impl).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'kokoro_backend.dart';
import 'kokoro_voices.dart';

/// Runs the Kokoro ONNX model with onnxruntime (bundled native lib). Lazily
/// loads the model + voice tables on first use so construction stays cheap.
///
/// Inference contract (kokoro-v1.0): inputs `tokens` (int64, the phoneme tokens
/// wrapped with a leading/trailing 0), `style` (float32 [1,256], the voice's row
/// for the token count), `speed` (float32 [1]); output `audio` is a mono 24 kHz
/// waveform.
class KokoroOrtSession implements KokoroSession {
  /// Path to the `.onnx` model.
  final String modelPath;

  /// Path to the `voices-*.bin` npz.
  final String voicesPath;

  OrtSession? _session;
  KokoroVoices? _voices;

  KokoroOrtSession({required this.modelPath, required this.voicesPath});

  @override
  int get sampleRate => 24000;

  Future<void> _ensureLoaded() async {
    if (_session != null) return;
    _voices = KokoroVoices.parse(File(voicesPath).readAsBytesSync());
    _session = await OnnxRuntime().createSession(modelPath);
  }

  @override
  Future<List<double>> infer(
      List<int> tokens, String voiceId, double speed) async {
    await _ensureLoaded();
    final session = _session!;
    final voices = _voices!;

    // Kokoro caps sequences at 510 tokens; trim defensively.
    final trimmed = tokens.length > 510 ? tokens.sublist(0, 510) : tokens;
    final ids = Int64List.fromList([0, ...trimmed, 0]);
    final style = voices.styleFor(voiceId, trimmed.length);

    final tokensValue = await OrtValue.fromList(ids, [1, ids.length]);
    final styleValue =
        await OrtValue.fromList(style, [1, KokoroVoices.dim]);
    final speedValue = await OrtValue.fromList(
        Float32List.fromList([speed <= 0 ? 1.0 : speed]), [1]);

    try {
      final outputs = await session.run({
        'tokens': tokensValue,
        'style': styleValue,
        'speed': speedValue,
      });
      final audio = outputs['audio'] ?? outputs.values.first;
      final flat = await audio.asFlattenedList();
      for (final o in outputs.values) {
        await o.dispose();
      }
      return [for (final v in flat) (v as num).toDouble()];
    } finally {
      await tokensValue.dispose();
      await styleValue.dispose();
      await speedValue.dispose();
    }
  }

  /// Releases the session.
  Future<void> dispose() async {
    await _session?.close();
    _session = null;
  }
}
