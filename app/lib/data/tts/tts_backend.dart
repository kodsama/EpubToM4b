/// The common interface every TTS engine implements.
///
/// Adding a backend means writing one class against this interface and adding
/// its voices to the catalog — the conversion controller and UI never change.
library;

import '../../domain/voice.dart';

/// Turns text into a mono WAV file at [sampleRate] Hz.
abstract class TtsBackend {
  /// Output sample rate of the WAV files this backend produces.
  int get sampleRate;

  /// Maximum characters per synthesis request; the chunker splits to this.
  int get maxChars;

  /// Languages this backend can narrate (for the language dropdown).
  List<Language> get supportedLanguages;

  /// Voices available for [languageCode] (for the voice dropdown).
  List<Voice> voicesFor(String languageCode);

  /// Synthesizes [text] into [outWavPath] as a mono WAV at [sampleRate].
  ///
  /// Implementations must produce a readable WAV even for empty/degenerate
  /// input (e.g. a short silent clip) so chapter assembly never fails.
  Future<void> synth(String text, String outWavPath);
}
