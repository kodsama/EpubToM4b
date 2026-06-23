/// Parsed-book domain models: [Book] and [Chapter].
///
/// Produced by the EPUB pipeline and consumed by the conversion controller and
/// the UI. Pure data — no Flutter or IO dependencies.
library;

import 'dart:typed_data';

/// One narratable section of a book, in spine (reading) order.
class Chapter {
  /// Zero-based position in the book's reading order.
  final int index;

  /// Display title (from the first heading, or a generated fallback).
  final String title;

  /// Cleaned, narration-ready plain text.
  final String text;

  const Chapter({required this.index, required this.title, required this.text});

  /// Number of characters to narrate, counted by Unicode code points so that
  /// accented French text is weighted the same way the chunker sees it. Used
  /// to weight global progress by actual narration work.
  int get charCount => text.runes.length;

  @override
  String toString() => 'Chapter($index, "$title", $charCount chars)';
}

/// A fully parsed book: metadata, optional embedded cover, and chapters.
class Book {
  /// Book title (falls back to the file stem when metadata is absent).
  final String title;

  /// Author / creator (falls back to a localized "Unknown").
  final String author;

  /// ISO 639-1 language code from EPUB metadata, defaulting to `en`.
  final String languageCode;

  /// Raw bytes of the cover image extracted from the EPUB, if any.
  final Uint8List? coverBytes;

  /// MIME type of [coverBytes] (e.g. `image/jpeg`), if a cover was found.
  final String? coverContentType;

  /// Chapters in reading order.
  final List<Chapter> chapters;

  const Book({
    required this.title,
    required this.author,
    required this.languageCode,
    required this.chapters,
    this.coverBytes,
    this.coverContentType,
  });

  /// Total characters across every chapter — the denominator for global
  /// progress when all chapters are selected.
  int get totalChars =>
      chapters.fold(0, (sum, c) => sum + c.charCount);

  /// Whether an embedded cover image is available.
  bool get hasCover => coverBytes != null && coverBytes!.isNotEmpty;

  @override
  String toString() =>
      'Book("$title" by $author, $languageCode, ${chapters.length} chapters)';
}
