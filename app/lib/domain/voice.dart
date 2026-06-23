/// Language and voice descriptors shared across TTS backends.
///
/// These are pure value types with no dependency on any particular backend
/// implementation, so the UI and the conversion pipeline can reason about
/// "what languages/voices are available" without importing backend code.
library;

import 'conversion_options.dart' show TtsBackendKind;

/// A spoken language a backend can narrate, identified by its ISO 639-1 code.
class Language {
  /// ISO 639-1 code, e.g. `fr`, `en`.
  final String code;

  /// Human-readable label shown in the UI, e.g. `Français`.
  final String label;

  const Language(this.code, this.label);

  @override
  bool operator ==(Object other) =>
      other is Language && other.code == code && other.label == label;

  @override
  int get hashCode => Object.hash(code, label);

  @override
  String toString() => 'Language($code, $label)';
}

/// A concrete voice offered by a specific [TtsBackendKind] for one language.
class Voice {
  /// Backend-specific identifier (Piper `.onnx` stem, OpenAI voice name,
  /// ElevenLabs voice id, or Kokoro voice key).
  final String id;

  /// Human-readable label shown in the UI.
  final String label;

  /// ISO 639-1 language code this voice speaks.
  final String languageCode;

  /// The backend that provides this voice.
  final TtsBackendKind backend;

  const Voice({
    required this.id,
    required this.label,
    required this.languageCode,
    required this.backend,
  });

  @override
  bool operator ==(Object other) =>
      other is Voice &&
      other.id == id &&
      other.backend == backend &&
      other.languageCode == languageCode;

  @override
  int get hashCode => Object.hash(id, backend, languageCode);

  @override
  String toString() => 'Voice($id, $languageCode, $backend)';
}
