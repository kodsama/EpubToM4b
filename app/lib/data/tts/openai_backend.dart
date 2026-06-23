/// OpenAI cloud TTS backend (`gpt-4o-mini-tts`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/conversion_options.dart';
import '../../domain/voice.dart';
import 'tts_backend.dart';
import 'voice_catalog.dart';

/// Synthesizes speech via OpenAI's `/v1/audio/speech` endpoint, requesting WAV
/// directly. French/English narration instructions are sent for the
/// instruction-aware model (mirrors the Python `OpenAIBackend`).
class OpenAiBackend extends TtsBackend {
  final http.Client _client;

  /// API key (from the UI / `OPENAI_API_KEY`).
  final String apiKey;

  /// Voice name, e.g. `alloy`.
  final String voice;

  /// TTS model id.
  final String model;

  /// Narration speed (0.25–4.0 per the API).
  final double speed;

  /// Endpoint, overridable for tests.
  final Uri endpoint;

  OpenAiBackend({
    required http.Client client,
    required this.apiKey,
    this.voice = 'alloy',
    this.model = 'gpt-4o-mini-tts',
    this.speed = 1.0,
    Uri? endpoint,
  })  : _client = client,
        endpoint = endpoint ?? Uri.parse('https://api.openai.com/v1/audio/speech');

  @override
  int get sampleRate => 24000;

  @override
  int get maxChars => 3500;

  @override
  List<Language> get supportedLanguages =>
      VoiceCatalog.languages(TtsBackendKind.openai);

  @override
  List<Voice> voicesFor(String languageCode) =>
      VoiceCatalog.voices(TtsBackendKind.openai, languageCode);

  @override
  Future<void> synth(String text, String outWavPath) async {
    final body = <String, dynamic>{
      'model': model,
      'voice': voice,
      'input': text,
      'response_format': 'wav',
      'speed': speed,
      if (model == 'gpt-4o-mini-tts')
        'instructions':
            'Read this text with clear, natural, measured diction in an '
                'audiobook narration tone, in the text\'s own language.',
    };
    final resp = await _client.post(
      endpoint,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) {
      throw HttpException(
          'OpenAI TTS failed (${resp.statusCode}): ${resp.body}');
    }
    await File(outWavPath).writeAsBytes(resp.bodyBytes);
  }
}
