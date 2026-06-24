/// Builds the concrete [TtsBackend] selected in [ConversionOptions].
library;

import 'package:http/http.dart' as http;

import '../../domain/conversion_options.dart';
import '../deps/sherpa_model_installer.dart';
import '../process_runner.dart';
import 'elevenlabs_backend.dart';
import 'openai_backend.dart';
import 'sherpa_catalog.dart';
import 'sherpa_tts_backend.dart';
import 'tts_backend.dart';

/// Resolves [options.backend] into a ready-to-use [TtsBackend].
///
/// For the `local` engine, `options.voiceId` is the sherpa model id; the model
/// is run via [SherpaTtsBackend] using files from [sherpa]. Cloud engines read
/// their key from `options.apiKeys`.
TtsBackend makeBackend(
  ConversionOptions options, {
  required ProcessRunner runner,
  required http.Client httpClient,
  required SherpaModelInstaller sherpa,
}) {
  switch (options.backend) {
    case TtsBackendKind.local:
      final model = sherpaModelById(options.voiceId) ??
          (throw StateError('Unknown local model: ${options.voiceId}'));
      return SherpaTtsBackend(
        model: model,
        languageCode: options.languageCode,
        installer: sherpa,
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
  }
}
