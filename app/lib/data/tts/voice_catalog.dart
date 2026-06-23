/// Static catalog of known voices and languages per backend.
///
/// This is the single place to extend language/voice coverage: add an entry
/// here and the UI dropdowns and backends pick it up automatically.
library;

import '../../domain/conversion_options.dart';
import '../../domain/voice.dart';

/// Lookups for which languages and voices each [TtsBackendKind] offers.
class VoiceCatalog {
  /// Human labels for language codes used across the app.
  static const Map<String, String> languageLabels = {
    'fr': 'Français',
    'en': 'English',
    'es': 'Español',
    'de': 'Deutsch',
    'it': 'Italiano',
    'pt': 'Português',
  };

  /// All voices known to the app, grouped implicitly by their fields.
  static const List<Voice> _all = [
    // --- Piper (local). `id` is the voice model stem in the models dir. ---
    Voice(id: 'fr_FR-siwis-medium', label: 'Siwis (FR, medium)', languageCode: 'fr', backend: TtsBackendKind.piper),
    Voice(id: 'fr_FR-upmc-medium', label: 'UPMC (FR, medium)', languageCode: 'fr', backend: TtsBackendKind.piper),
    Voice(id: 'en_US-amy-medium', label: 'Amy (US, medium)', languageCode: 'en', backend: TtsBackendKind.piper),
    Voice(id: 'en_GB-alan-medium', label: 'Alan (GB, medium)', languageCode: 'en', backend: TtsBackendKind.piper),

    // --- Kokoro (local ONNX). `id` is the Kokoro voice key. ---
    Voice(id: 'ff_siwis', label: 'Siwis (FR)', languageCode: 'fr', backend: TtsBackendKind.kokoro),
    Voice(id: 'af_heart', label: 'Heart (US)', languageCode: 'en', backend: TtsBackendKind.kokoro),
    Voice(id: 'am_michael', label: 'Michael (US)', languageCode: 'en', backend: TtsBackendKind.kokoro),

    // --- OpenAI (cloud). Voices are language-agnostic (multilingual model). ---
    Voice(id: 'alloy', label: 'Alloy', languageCode: 'fr', backend: TtsBackendKind.openai),
    Voice(id: 'nova', label: 'Nova', languageCode: 'fr', backend: TtsBackendKind.openai),
    Voice(id: 'alloy', label: 'Alloy', languageCode: 'en', backend: TtsBackendKind.openai),
    Voice(id: 'nova', label: 'Nova', languageCode: 'en', backend: TtsBackendKind.openai),

    // --- ElevenLabs (cloud). Default multilingual voice ids. ---
    Voice(id: 'EXAVITQu4vr4xnSDxMaL', label: 'Sarah (multilingual)', languageCode: 'fr', backend: TtsBackendKind.elevenlabs),
    Voice(id: 'EXAVITQu4vr4xnSDxMaL', label: 'Sarah (multilingual)', languageCode: 'en', backend: TtsBackendKind.elevenlabs),
  ];

  /// Voices for [backend] that speak [languageCode].
  static List<Voice> voices(TtsBackendKind backend, String languageCode) => _all
      .where((v) => v.backend == backend && v.languageCode == languageCode)
      .toList();

  /// Distinct language codes [backend] supports.
  static List<Language> languages(TtsBackendKind backend) {
    final codes = <String>{
      for (final v in _all)
        if (v.backend == backend) v.languageCode,
    };
    return [
      for (final c in codes) Language(c, languageLabels[c] ?? c.toUpperCase()),
    ];
  }

  /// The default voice id for [backend]+[languageCode], or empty if none.
  static String defaultVoiceId(TtsBackendKind backend, String languageCode) {
    final vs = voices(backend, languageCode);
    return vs.isEmpty ? '' : vs.first.id;
  }
}
