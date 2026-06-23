/// ElevenLabs cloud TTS backend (`eleven_multilingual_v2`).
library;

import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/conversion_options.dart';
import '../../domain/voice.dart';
import '../audio/wav_writer.dart';
import 'tts_backend.dart';
import 'voice_catalog.dart';

/// Synthesizes speech via ElevenLabs, requesting raw 44.1 kHz PCM and wrapping
/// it in a WAV header so the pipeline handles every backend uniformly (mirrors
/// the Python `ElevenLabsBackend`).
class ElevenLabsBackend extends TtsBackend {
  final http.Client _client;

  /// API key (from the UI / `ELEVENLABS_API_KEY`).
  final String apiKey;

  /// Target voice id.
  final String voiceId;

  /// Model id.
  final String model;

  /// Base endpoint (without the voice id), overridable for tests.
  final Uri baseEndpoint;

  ElevenLabsBackend({
    required http.Client client,
    required this.apiKey,
    required this.voiceId,
    this.model = 'eleven_multilingual_v2',
    Uri? baseEndpoint,
  })  : _client = client,
        baseEndpoint =
            baseEndpoint ?? Uri.parse('https://api.elevenlabs.io/v1/text-to-speech');

  @override
  int get sampleRate => 44100;

  @override
  int get maxChars => 2500;

  @override
  List<Language> get supportedLanguages =>
      VoiceCatalog.languages(TtsBackendKind.elevenlabs);

  @override
  List<Voice> voicesFor(String languageCode) =>
      VoiceCatalog.voices(TtsBackendKind.elevenlabs, languageCode);

  @override
  Future<void> synth(String text, String outWavPath) async {
    final uri = Uri.parse('$baseEndpoint/$voiceId?output_format=pcm_44100');
    final resp = await _client.post(
      uri,
      headers: {
        'xi-api-key': apiKey,
        'Content-Type': 'application/json',
      },
      body: '{"text":${_jsonString(text)},"model_id":"$model"}',
    );
    if (resp.statusCode != 200) {
      throw HttpException(
          'ElevenLabs TTS failed (${resp.statusCode}): ${resp.body}');
    }
    final wav = buildWavPcm16Mono(resp.bodyBytes, sampleRate);
    await File(outWavPath).writeAsBytes(wav);
  }

  /// Minimal JSON string escaping for the request body.
  String _jsonString(String s) {
    final escaped = s
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
    return '"$escaped"';
  }
}
