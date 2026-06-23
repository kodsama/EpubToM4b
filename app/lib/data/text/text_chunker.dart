/// Groups sentences into TTS-sized chunks.
library;

import 'sentence_splitter.dart';

/// Splits a chapter's text into chunks no longer than `maxChars`, keeping whole
/// sentences together when possible so the TTS engine stays stable and within
/// its per-request limit.
///
/// Ported from `epub_to_m4b.py` `chunk_text`: sentences are accumulated until
/// adding the next would exceed `maxChars`; a single sentence longer than
/// `maxChars` is hard-split on character boundaries.
class TextChunker {
  final SentenceSplitter _splitter;

  /// Creates a chunker, optionally with a custom [splitter] (for testing).
  TextChunker({SentenceSplitter? splitter})
      : _splitter = splitter ?? SentenceSplitter();

  /// Returns chunks of [text], each with `length <= maxChars`.
  List<String> chunk(
    String text, {
    required int maxChars,
    String languageCode = 'en',
  }) {
    final chunks = <String>[];
    var current = '';

    void flush() {
      if (current.isNotEmpty) {
        chunks.add(current);
        current = '';
      }
    }

    for (final sentence in _splitter.split(text, languageCode: languageCode)) {
      if (sentence.length > maxChars) {
        // Oversized single sentence: emit what we have, then hard-split it.
        flush();
        for (var i = 0; i < sentence.length; i += maxChars) {
          final end =
              (i + maxChars < sentence.length) ? i + maxChars : sentence.length;
          chunks.add(sentence.substring(i, end));
        }
        continue;
      }
      // +1 accounts for the joining space.
      if (current.isEmpty) {
        current = sentence;
      } else if (current.length + sentence.length + 1 <= maxChars) {
        current = '$current $sentence';
      } else {
        flush();
        current = sentence;
      }
    }
    flush();
    return chunks;
  }
}
