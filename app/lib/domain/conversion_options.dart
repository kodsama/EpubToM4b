/// User-selected conversion settings: [ConversionOptions] and [TtsBackendKind].
library;

import 'book.dart';

/// The available text-to-speech engines, all behind one common interface.
enum TtsBackendKind {
  /// Local, free, standalone binary with per-language `.onnx` voices.
  piper,

  /// Local ONNX model (highest local quality), needs espeak-ng + onnxruntime.
  kokoro,

  /// Cloud, OpenAI `gpt-4o-mini-tts` over HTTP.
  openai,

  /// Cloud, ElevenLabs `eleven_multilingual_v2` over HTTP.
  elevenlabs;

  /// Whether this backend talks to a remote API (and thus needs an API key
  /// rather than a locally installed binary/model).
  bool get isCloud => this == openai || this == elevenlabs;

  /// Short label for the UI.
  String get label => switch (this) {
        TtsBackendKind.piper => 'Piper (local, free)',
        TtsBackendKind.kokoro => 'Kokoro (local, ONNX)',
        TtsBackendKind.openai => 'OpenAI (cloud)',
        TtsBackendKind.elevenlabs => 'ElevenLabs (cloud)',
      };
}

/// Immutable bundle of every choice that drives a single conversion run.
///
/// Build the sensible starting point with [ConversionOptions.defaults] and
/// produce modified copies with [copyWith] as the user adjusts the UI.
class ConversionOptions {
  /// Selected TTS engine.
  final TtsBackendKind backend;

  /// ISO 639-1 language code the narration should use.
  final String languageCode;

  /// Backend-specific voice id (see `Voice.id`).
  final String voiceId;

  /// Narration speed multiplier (0.5–2.0; 1.0 = natural).
  final double speed;

  /// AAC bitrate for the output, e.g. `128k`.
  final String bitrate;

  /// Absolute path of the `.m4b` file to write.
  final String outputPath;

  /// Optional cover image path that overrides the EPUB's embedded cover.
  final String? coverOverridePath;

  /// Indices of the chapters the user chose to include.
  final Set<int> selectedChapterIndices;

  /// Directory where per-chapter WAVs are cached for resume.
  final String workDir;

  /// API keys keyed by backend name (only used by cloud backends).
  final Map<String, String> apiKeys;

  const ConversionOptions({
    required this.backend,
    required this.languageCode,
    required this.voiceId,
    required this.speed,
    required this.bitrate,
    required this.outputPath,
    required this.selectedChapterIndices,
    required this.workDir,
    this.coverOverridePath,
    this.apiKeys = const {},
  });

  /// Best-practice defaults for [book]: the free local Piper backend, the
  /// book's own language, natural speed, 128k bitrate, and every chapter
  /// selected. [outputPath] and [workDir] are supplied by the caller because
  /// they depend on the host filesystem.
  factory ConversionOptions.defaults(
    Book book, {
    required String outputPath,
    required String workDir,
    String voiceId = '',
  }) {
    return ConversionOptions(
      backend: TtsBackendKind.piper,
      languageCode: book.languageCode,
      voiceId: voiceId,
      speed: 1.0,
      bitrate: '128k',
      outputPath: outputPath,
      workDir: workDir,
      selectedChapterIndices:
          book.chapters.map((c) => c.index).toSet(),
    );
  }

  /// Returns a copy with the provided fields replaced.
  ConversionOptions copyWith({
    TtsBackendKind? backend,
    String? languageCode,
    String? voiceId,
    double? speed,
    String? bitrate,
    String? outputPath,
    String? coverOverridePath,
    Set<int>? selectedChapterIndices,
    String? workDir,
    Map<String, String>? apiKeys,
  }) {
    return ConversionOptions(
      backend: backend ?? this.backend,
      languageCode: languageCode ?? this.languageCode,
      voiceId: voiceId ?? this.voiceId,
      speed: speed ?? this.speed,
      bitrate: bitrate ?? this.bitrate,
      outputPath: outputPath ?? this.outputPath,
      coverOverridePath: coverOverridePath ?? this.coverOverridePath,
      selectedChapterIndices:
          selectedChapterIndices ?? this.selectedChapterIndices,
      workDir: workDir ?? this.workDir,
      apiKeys: apiKeys ?? this.apiKeys,
    );
  }
}
