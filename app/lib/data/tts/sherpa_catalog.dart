/// Catalog of local TTS engines runnable via sherpa-onnx.
///
/// An *engine* ([SherpaModel]) bundles one or more per-language *voices*
/// ([SherpaVoice]). Installing an engine downloads all its voices, and at
/// synthesis time the voice matching the book's language is used. Each voice
/// knows where to download its archive and how its files map onto a sherpa
/// `OfflineTtsModelConfig` (the family decides which sub-config is used).
library;

/// Which sherpa model family a voice belongs to (selects the sub-config).
enum SherpaFamily { vits, kokoro, matcha, kitten }

/// A single downloadable per-language sub-model.
class SherpaVoice {
  /// Languages this voice speaks (ISO 639-1). Most are single-language; Kokoro
  /// covers several.
  final List<String> languages;

  /// Model family (drives the sherpa config).
  final SherpaFamily family;

  /// Output sample rate (Hz).
  final int sampleRate;

  /// Approximate download size (MB).
  final int sizeMb;

  /// Archive URL (`.tar.bz2`).
  final String archiveUrl;

  /// Extracted top-level folder name.
  final String dirName;

  /// Main model file (for Matcha, the acoustic model), relative to [dirName].
  final String modelFile;

  /// Tokens file, relative to [dirName].
  final String tokensFile;

  /// espeak-ng-data dir (relative), or '' (e.g. MMS).
  final String dataDir;

  /// Kokoro/Kitten voices file (relative), or ''.
  final String voicesFile;

  /// Comma-separated lexicon files (relative), or ''.
  final String lexicon;

  /// Kokoro language hint, or ''.
  final String lang;

  /// Matcha vocoder archive URL, or ''.
  final String vocoderUrl;

  /// Matcha vocoder file name (relative), or ''.
  final String vocoderFile;

  const SherpaVoice({
    required this.languages,
    required this.family,
    required this.sampleRate,
    required this.sizeMb,
    required this.archiveUrl,
    required this.dirName,
    required this.modelFile,
    required this.tokensFile,
    this.dataDir = '',
    this.voicesFile = '',
    this.lexicon = '',
    this.lang = '',
    this.vocoderUrl = '',
    this.vocoderFile = '',
  });

  /// Whether this voice can speak [languageCode].
  bool speaks(String languageCode) => languages.contains(languageCode);
}

/// A local TTS engine: a label, guidance, and one or more language voices.
class SherpaModel {
  /// Stable id (used as the selected "voice" in options).
  final String id;

  /// Human-readable label.
  final String label;

  /// One-line guidance: what it's good at / less good at.
  final String blurb;

  /// Whether this is the suggested default (exactly one entry sets this).
  final bool recommended;

  /// Per-language voices bundled in this engine.
  final List<SherpaVoice> voices;

  const SherpaModel({
    required this.id,
    required this.label,
    required this.blurb,
    required this.voices,
    this.recommended = false,
  });

  /// All languages this engine covers (deduped, in declaration order).
  List<String> get languages {
    final seen = <String>{};
    final out = <String>[];
    for (final v in voices) {
      for (final l in v.languages) {
        if (seen.add(l)) out.add(l);
      }
    }
    return out;
  }

  /// Total download size across all voices.
  int get sizeMb => voices.fold(0, (sum, v) => sum + v.sizeMb);

  /// The voice for [languageCode] (exact match), else the first voice.
  SherpaVoice voiceFor(String languageCode) {
    for (final v in voices) {
      if (v.speaks(languageCode)) return v;
    }
    return voices.first;
  }
}

const String _rel =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models';
const String _voc =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/vocoder-models';

// --- Individual voices ---

const _piperFr = SherpaVoice(
  languages: ['fr'],
  family: SherpaFamily.vits,
  sampleRate: 22050,
  sizeMb: 64,
  archiveUrl: '$_rel/vits-piper-fr_FR-siwis-medium.tar.bz2',
  dirName: 'vits-piper-fr_FR-siwis-medium',
  modelFile: 'fr_FR-siwis-medium.onnx',
  tokensFile: 'tokens.txt',
  dataDir: 'espeak-ng-data',
);
const _piperEn = SherpaVoice(
  languages: ['en'],
  family: SherpaFamily.vits,
  sampleRate: 22050,
  sizeMb: 64,
  archiveUrl: '$_rel/vits-piper-en_US-amy-medium.tar.bz2',
  dirName: 'vits-piper-en_US-amy-medium',
  modelFile: 'en_US-amy-medium.onnx',
  tokensFile: 'tokens.txt',
  dataDir: 'espeak-ng-data',
);
const _mmsFr = SherpaVoice(
  languages: ['fr'],
  family: SherpaFamily.vits,
  sampleRate: 16000,
  sizeMb: 103,
  archiveUrl: '$_rel/vits-mms-fra.tar.bz2',
  dirName: 'vits-mms-fra',
  modelFile: 'model.onnx',
  tokensFile: 'tokens.txt',
);
const _mmsEn = SherpaVoice(
  languages: ['en'],
  family: SherpaFamily.vits,
  sampleRate: 16000,
  sizeMb: 103,
  archiveUrl: '$_rel/vits-mms-eng.tar.bz2',
  dirName: 'vits-mms-eng',
  modelFile: 'model.onnx',
  tokensFile: 'tokens.txt',
);
const _kokoro = SherpaVoice(
  languages: ['en', 'fr', 'es', 'it', 'pt', 'zh'],
  family: SherpaFamily.kokoro,
  sampleRate: 24000,
  sizeMb: 380,
  archiveUrl: '$_rel/kokoro-multi-lang-v1_0.tar.bz2',
  dirName: 'kokoro-multi-lang-v1_0',
  modelFile: 'model.onnx',
  tokensFile: 'tokens.txt',
  dataDir: 'espeak-ng-data',
  voicesFile: 'voices.bin',
  lexicon: 'lexicon-us-en.txt,lexicon-zh.txt',
  lang: 'en-us',
);
const _matchaEn = SherpaVoice(
  languages: ['en'],
  family: SherpaFamily.matcha,
  sampleRate: 22050,
  sizeMb: 73,
  archiveUrl: '$_rel/matcha-icefall-en_US-ljspeech.tar.bz2',
  dirName: 'matcha-icefall-en_US-ljspeech',
  modelFile: 'model-steps-3.onnx',
  tokensFile: 'tokens.txt',
  dataDir: 'espeak-ng-data',
  vocoderUrl: '$_voc/vocos-22khz-univ.onnx',
  vocoderFile: 'vocos-22khz-univ.onnx',
);
const _kittenEn = SherpaVoice(
  languages: ['en'],
  family: SherpaFamily.kitten,
  sampleRate: 24000,
  sizeMb: 25,
  archiveUrl: '$_rel/kitten-nano-en-v0_1-fp16.tar.bz2',
  dirName: 'kitten-nano-en-v0_1-fp16',
  modelFile: 'model.fp16.onnx',
  tokensFile: 'tokens.txt',
  dataDir: 'espeak-ng-data',
  voicesFile: 'voices.bin',
);

/// All local engines. Installing one downloads every language it bundles.
const List<SherpaModel> kSherpaModels = [
  SherpaModel(
    id: 'piper',
    label: 'Piper',
    recommended: true,
    blurb: 'Fast, light, fully offline. Clear and natural for everyday '
        'listening. Less expressive than Kokoro. Best all-round default.',
    voices: [_piperFr, _piperEn],
  ),
  SherpaModel(
    id: 'kokoro',
    label: 'Kokoro',
    blurb: 'Highest quality — natural and expressive across many languages. '
        'Larger download (~380 MB) and slower on CPU.',
    voices: [_kokoro],
  ),
  SherpaModel(
    id: 'mms',
    label: 'MMS',
    blurb: 'Widest language coverage (Meta MMS, 1000+ languages). Decent but a '
        'bit robotic. Use when other engines lack your language.',
    voices: [_mmsFr, _mmsEn],
  ),
  SherpaModel(
    id: 'matcha',
    label: 'Matcha',
    blurb: 'Fast and high quality, English only here. Includes a small vocoder.',
    voices: [_matchaEn],
  ),
  SherpaModel(
    id: 'kitten',
    label: 'Kitten',
    blurb: 'Tiny and quick (~25 MB), lower fidelity. Good for low-end machines '
        'or a fast test. English only.',
    voices: [_kittenEn],
  ),
];

/// Engines that can speak [languageCode].
List<SherpaModel> sherpaModelsFor(String languageCode) =>
    kSherpaModels.where((m) => m.languages.contains(languageCode)).toList();

/// Looks up an engine by id, or null.
SherpaModel? sherpaModelById(String id) {
  for (final m in kSherpaModels) {
    if (m.id == id) return m;
  }
  return null;
}

/// The default engine id for a language: the recommended one if it speaks the
/// language, else the first engine that does, else the recommended one.
String defaultSherpaModelId(String languageCode) {
  final rec = kSherpaModels.firstWhere((m) => m.recommended,
      orElse: () => kSherpaModels.first);
  if (rec.languages.contains(languageCode)) return rec.id;
  final forLang = sherpaModelsFor(languageCode);
  return forLang.isNotEmpty ? forLang.first.id : rec.id;
}
