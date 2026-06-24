/// Kokoro local TTS backend (ONNX), built around injectable seams.
///
/// Kokoro has two stages: text → phonemes (via `espeak-ng`) and phonemes →
/// audio (via an ONNX model). The phoneme stage and audio assembly are pure
/// Dart and fully unit-tested here; the neural inference is hidden behind the
/// [KokoroSession] interface so the native onnxruntime can be supplied (and
/// verified) without changing this class. See ARCHITECTURE.md §Kokoro.
library;

import 'dart:io';

import '../../domain/conversion_options.dart';
import '../../domain/voice.dart';
import '../audio/wav_writer.dart';
import '../process_runner.dart';
import 'kokoro_vocab.g.dart';
import 'tts_backend.dart';
import 'voice_catalog.dart';

/// Runs Kokoro ONNX inference: phoneme token ids → float audio samples.
///
/// Implemented in production by an onnxruntime-backed class that loads the
/// downloaded `kokoro.onnx` model + voice pack. Tests provide a fake.
abstract class KokoroSession {
  /// Output sample rate of the model (Kokoro is 24 kHz).
  int get sampleRate;

  /// Runs inference for [tokens] with [voiceId] at [speed], returning mono
  /// float samples in `[-1, 1]`.
  Future<List<double>> infer(List<int> tokens, String voiceId, double speed);
}

/// Maps espeak IPA phonemes to model token ids.
///
/// NOTE: the authoritative vocabulary ships with a specific Kokoro model
/// revision. This deterministic fallback assigns a stable id per phoneme so the
/// pipeline is exercisable end-to-end; swap in the model's real vocab map when
/// wiring [KokoroSession] to onnxruntime.
class KokoroVocab {
  final Map<String, int> _map;
  const KokoroVocab(this._map);

  /// The canonical Kokoro vocab (generated from the model's `config.json`).
  factory KokoroVocab.fallback() => const KokoroVocab(kKokoroVocab);

  /// Tokenizes an IPA [phonemes] string, dropping unknown symbols.
  List<int> tokenize(String phonemes) =>
      [for (final ch in phonemes.split('')) if (_map.containsKey(ch)) _map[ch]!];
}

/// Local Kokoro backend.
class KokoroBackend extends TtsBackend {
  final ProcessRunner _runner;
  final KokoroSession _session;
  final KokoroVocab _vocab;

  /// espeak-ng executable.
  final String espeakBin;

  /// espeak voice/language code (e.g. `fr`, `en`).
  final String languageCode;

  /// Kokoro voice key (see [VoiceCatalog]).
  final String voiceId;

  /// Narration speed multiplier passed to inference.
  final double speed;

  KokoroBackend({
    required ProcessRunner runner,
    required KokoroSession session,
    required this.languageCode,
    required this.voiceId,
    this.speed = 1.0,
    this.espeakBin = 'espeak-ng',
    KokoroVocab? vocab,
  })  : _runner = runner,
        _session = session,
        _vocab = vocab ?? KokoroVocab.fallback();

  @override
  int get sampleRate => _session.sampleRate;

  @override
  int get maxChars => 1800;

  @override
  List<Language> get supportedLanguages =>
      VoiceCatalog.languages(TtsBackendKind.kokoro);

  @override
  List<Voice> voicesFor(String languageCode) =>
      VoiceCatalog.voices(TtsBackendKind.kokoro, languageCode);

  /// espeak-ng voice for a Kokoro language code (Kokoro voices are fr-fr/en-us).
  static String espeakVoice(String languageCode) => switch (languageCode) {
        'fr' => 'fr-fr',
        'en' => 'en-us',
        _ => languageCode,
      };

  /// Converts [text] to IPA phonemes via espeak-ng (`-q --ipa`).
  Future<String> phonemize(String text) async {
    final r = await _runner.checked(
      espeakBin,
      ['-q', '--ipa', '-v', espeakVoice(languageCode)],
      stdinText: text,
    );
    return r.stdout.replaceAll('\n', ' ').trim();
  }

  @override
  Future<void> synth(String text, String outWavPath) async {
    final phonemes = await phonemize(text);
    final tokens = _vocab.tokenize(phonemes);
    final samples = await _session.infer(tokens, voiceId, speed);
    final pcm = floatToPcm16(samples);
    await File(outWavPath).writeAsBytes(buildWavPcm16Mono(pcm, sampleRate));
  }
}
