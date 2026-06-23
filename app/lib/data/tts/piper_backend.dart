/// Piper local TTS backend — drives the standalone `piper` binary.
library;

import '../../domain/conversion_options.dart';
import '../../domain/voice.dart';
import '../process_runner.dart';
import 'tts_backend.dart';
import 'voice_catalog.dart';

/// Synthesizes speech with the [Piper](https://github.com/rhasspy/piper) binary.
///
/// Piper reads text on stdin and writes a mono WAV to `--output_file`. A voice
/// is a `<name>.onnx` model (plus a sibling `.onnx.json`); narration speed maps
/// to Piper's inverse `--length_scale`.
class PiperBackend extends TtsBackend {
  final ProcessRunner _runner;

  /// Path/name of the piper executable.
  final String piperBin;

  /// Absolute path to the selected voice `.onnx` model.
  final String modelPath;

  /// Piper length scale (1 / speed); >1 slows speech down.
  final double lengthScale;

  PiperBackend({
    required ProcessRunner runner,
    required this.modelPath,
    this.piperBin = 'piper',
    double speed = 1.0,
  })  : _runner = runner,
        lengthScale = 1.0 / (speed <= 0 ? 1.0 : speed);

  @override
  int get sampleRate => 22050;

  @override
  int get maxChars => 2000;

  @override
  List<Language> get supportedLanguages =>
      VoiceCatalog.languages(TtsBackendKind.piper);

  @override
  List<Voice> voicesFor(String languageCode) =>
      VoiceCatalog.voices(TtsBackendKind.piper, languageCode);

  @override
  Future<void> synth(String text, String outWavPath) async {
    await _runner.checked(
      piperBin,
      [
        '--model', modelPath,
        '--length_scale', lengthScale.toString(),
        '--output_file', outWavPath,
      ],
      stdinText: text,
    );
  }
}
