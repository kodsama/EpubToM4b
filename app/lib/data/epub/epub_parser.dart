/// Top-level EPUB parser: archive bytes in, [Book] out.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;

import '../../domain/book.dart';
import 'content_cleaner.dart';
import 'cover_extractor.dart';
import 'opf_reader.dart';

/// Parses a DRM-free EPUB into a [Book], composing the focused readers
/// ([OpfReader], [ContentCleaner], [CoverExtractor]).
///
/// Mirrors `parse_epub` in `epub_to_m4b.py`: walk the spine (true reading
/// order), skip navigation/cover documents and near-empty sections, derive a
/// chapter title from the first heading, and clean the prose for narration.
class EpubParser {
  final OpfReader _opf;
  final ContentCleaner _cleaner;
  final CoverExtractor _cover;

  /// Minimum cleaned-text length for a spine document to count as a chapter.
  /// Filters out title pages, dedications and blank sections.
  static const int minChapterChars = 20;

  EpubParser({
    OpfReader? opfReader,
    ContentCleaner? cleaner,
    CoverExtractor? coverExtractor,
  })  : _opf = opfReader ?? OpfReader(),
        _cleaner = cleaner ?? ContentCleaner(),
        _cover = coverExtractor ?? CoverExtractor();

  /// Parses [epubBytes]. [fallbackTitle] (typically the file name without
  /// extension) is used when the EPUB declares no title.
  ///
  /// Throws [FormatException] when no readable chapters are found.
  Book parse(Uint8List epubBytes, {String fallbackTitle = 'Audiobook'}) {
    final archive = ZipDecoder().decodeBytes(epubBytes);
    final opf = _opf.read(archive);

    final chapters = <Chapter>[];
    for (final href in opf.spineHrefs) {
      final name = href.toLowerCase();
      if (name.contains('nav') ||
          name.contains('toc') ||
          name.contains('cover')) {
        continue;
      }
      final xhtml = _readString(archive, href);
      if (xhtml == null) continue;
      final text = _cleaner.toText(xhtml);
      if (text.length < minChapterChars) continue;
      chapters.add(Chapter(
        index: chapters.length,
        title: _titleOf(xhtml) ?? 'Chapter ${chapters.length + 1}',
        text: text,
      ));
    }

    if (chapters.isEmpty) {
      throw const FormatException(
          'No readable chapters found. Is the EPUB DRM-free and valid?');
    }

    final cover = _cover.extract(archive, opf);
    return Book(
      title: opf.title.isEmpty ? fallbackTitle : opf.title,
      author: opf.author.isEmpty ? 'Unknown' : opf.author,
      languageCode: opf.languageCode,
      chapters: chapters,
      coverBytes: cover?.bytes,
      coverContentType: cover?.contentType,
    );
  }

  /// First `h1`/`h2`/`h3` text in the document, if any.
  String? _titleOf(String xhtml) {
    final doc = html_parser.parse(xhtml);
    final heading = doc.querySelector('h1, h2, h3');
    final t = heading?.text.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  String? _readString(Archive archive, String path) {
    for (final f in archive.files) {
      if (f.name == path) {
        return utf8.decode(f.content as List<int>, allowMalformed: true);
      }
    }
    return null;
  }
}
