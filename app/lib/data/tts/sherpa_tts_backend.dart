/// Unified local TTS backend powered by sherpa-onnx.
///
/// One backend runs every local model family (VITS/Piper, MMS, Kokoro, Matcha,
/// Kitten): sherpa-onnx handles phonemization, tokenization and inference
/// internally. The engine bundles per-language voices; the voice matching the
/// conversion language is selected and its family selects the sub-config.
library;

import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../domain/voice.dart';
import '../audio/wav_writer.dart';
import '../deps/sherpa_model_installer.dart';
import 'sherpa_catalog.dart';
import 'tts_backend.dart';

/// A [TtsBackend] that synthesizes with a downloaded sherpa-onnx engine, using
/// the voice that matches [languageCode].
class SherpaTtsBackend extends TtsBackend {
  final SherpaModel model;
  final String languageCode;
  final SherpaModelInstaller installer;
  final double speed;
  final int numThreads;

  late final SherpaVoice _voice = model.voiceFor(languageCode);

  SherpaTtsBackend({
    required this.model,
    required this.languageCode,
    required this.installer,
    this.speed = 1.0,
    this.numThreads = 2,
  });

  static bool _bindingsReady = false;
  sherpa.OfflineTts? _tts;

  @override
  int get sampleRate => _voice.sampleRate;

  @override
  int get maxChars => 1800;

  @override
  List<Language> get supportedLanguages =>
      [for (final c in model.languages) Language(c, c.toUpperCase())];

  @override
  List<Voice> voicesFor(String languageCode) => const [];

  /// Builds the sherpa config for the selected voice's family and opens it.
  void _ensureLoaded() {
    if (_tts != null) return;
    if (!_bindingsReady) {
      sherpa.initBindings();
      _bindingsReady = true;
    }
    final v = _voice;
    final modelCfg = switch (v.family) {
      SherpaFamily.vits => sherpa.OfflineTtsModelConfig(
          vits: sherpa.OfflineTtsVitsModelConfig(
            model: installer.modelPath(v),
            tokens: installer.fileIn(v, v.tokensFile),
            dataDir: installer.fileIn(v, v.dataDir),
          ),
          numThreads: numThreads,
          debug: false,
        ),
      SherpaFamily.kokoro => sherpa.OfflineTtsModelConfig(
          kokoro: sherpa.OfflineTtsKokoroModelConfig(
            model: installer.modelPath(v),
            voices: installer.fileIn(v, v.voicesFile),
            tokens: installer.fileIn(v, v.tokensFile),
            dataDir: installer.fileIn(v, v.dataDir),
            lexicon: _joinLexicon(installer.dirOf(v), v.lexicon),
            lang: v.lang,
          ),
          numThreads: numThreads,
          debug: false,
        ),
      SherpaFamily.matcha => sherpa.OfflineTtsModelConfig(
          matcha: sherpa.OfflineTtsMatchaModelConfig(
            acousticModel: installer.modelPath(v),
            vocoder: installer.vocoderPath(v),
            tokens: installer.fileIn(v, v.tokensFile),
            dataDir: installer.fileIn(v, v.dataDir),
          ),
          numThreads: numThreads,
          debug: false,
        ),
      SherpaFamily.kitten => sherpa.OfflineTtsModelConfig(
          kitten: sherpa.OfflineTtsKittenModelConfig(
            model: installer.modelPath(v),
            voices: installer.fileIn(v, v.voicesFile),
            tokens: installer.fileIn(v, v.tokensFile),
            dataDir: installer.fileIn(v, v.dataDir),
          ),
          numThreads: numThreads,
          debug: false,
        ),
    };
    _tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(model: modelCfg));
  }

  /// Resolves comma-separated lexicon file names to absolute paths.
  static String _joinLexicon(String dir, String lexicon) {
    if (lexicon.isEmpty) return '';
    return lexicon.split(',').map((f) => '$dir/${f.trim()}').join(',');
  }

  @override
  Future<void> synth(String text, String outWavPath) async {
    _ensureLoaded();
    final audio = _tts!.generate(text: text, sid: 0, speed: speed);
    final pcm = floatToPcm16(audio.samples);
    await File(outWavPath).writeAsBytes(buildWavPcm16Mono(pcm, audio.sampleRate));
  }

  /// Releases the native engine.
  void dispose() {
    _tts?.free();
    _tts = null;
  }
}
