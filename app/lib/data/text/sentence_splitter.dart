/// Splits prose into sentences for chunk-aware TTS.
///
/// Ported and generalized from the original `epub_to_m4b.py` `split_sentences`,
/// whose regex was tuned for French (handles « », …). The same pattern works
/// for English; the [languageCode] parameter is accepted now so future
/// languages with different conventions can branch here without changing
/// callers.
library;

/// Splits text on sentence boundaries: whitespace that follows a terminator
/// (`.!?…»`) and precedes an opening quote, capital letter, or digit. Keeps
/// abbreviations and decimals mostly intact because the lookahead requires a
/// capital/quote/digit after the space.
class SentenceSplitter {
  /// Boundary between a terminator and the next sentence's opening character.
  static final RegExp _boundary = RegExp(
    r'(?<=[.!?…»])\s+(?=[«“"A-ZÀ-ÖØ-Þ0-9])',
  );

  /// Returns trimmed, non-empty sentences from [text]. [languageCode] is
  /// currently advisory (French/English share the same rules).
  List<String> split(String text, {String languageCode = 'en'}) {
    return text
        .split(_boundary)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}
