/// Builds the concrete [TtsBackend] selected in [ConversionOptions].
library;

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../domain/conversion_options.dart';
import '../process_runner.dart';
import 'elevenlabs_backend.dart';
import 'openai_backend.dart';
import 'piper_backend.dart';
import 'tts_backend.dart';

/// Resolves [options.backend] into a ready-to-use [TtsBackend].
///
/// [modelsDir] is where local models/voices live; cloud backends ignore it and
/// read their key from [options.apiKeys] (`openai` / `elevenlabs`).
///
/// Kokoro is constructed lazily by its own module (see `kokoro_backend.dart`)
/// once its native runtime is available; until then selecting it throws a clear
/// [UnimplementedError].
TtsBackend makeBackend(
  ConversionOptions options, {
  required ProcessRunner runner,
  required http.Client httpClient,
  required String modelsDir,
}) {
  switch (options.backend) {
    case TtsBackendKind.piper:
      final modelPath =
          p.join(modelsDir, 'piper', '${options.voiceId}.onnx');
      return PiperBackend(
        runner: runner,
        modelPath: modelPath,
        speed: options.speed,
      );
    case TtsBackendKind.openai:
      return OpenAiBackend(
        client: httpClient,
        apiKey: options.apiKeys['openai'] ?? '',
        voice: options.voiceId,
        speed: options.speed,
      );
    case TtsBackendKind.elevenlabs:
      return ElevenLabsBackend(
        client: httpClient,
        apiKey: options.apiKeys['elevenlabs'] ?? '',
        voiceId: options.voiceId,
      );
    case TtsBackendKind.kokoro:
      throw UnimplementedError(
          'Kokoro backend is initialized via KokoroBackend.load(); '
          'see data/tts/kokoro_backend.dart');
  }
}
