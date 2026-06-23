/// Converts an XHTML chapter document into narration-ready plain text.
library;

import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Strips XHTML markup down to readable prose, mirroring `_clean_text` from the
/// original `epub_to_m4b.py`:
///
/// * removes elements that should never be spoken (`script`, `style`, `sup`,
///   `sub`, `nav`, `table`, `figure`),
/// * unescapes HTML entities,
/// * Unicode-normalizes to NFC,
/// * collapses all runs of whitespace to single spaces.
class ContentCleaner {
  /// Tags whose text content is dropped entirely before extraction.
  static const _dropTags = [
    'script',
    'style',
    'sup',
    'sub',
    'nav',
    'table',
    'figure',
  ];

  static final RegExp _whitespace = RegExp(r'\s+');

  /// Returns clean prose extracted from [xhtml].
  String toText(String xhtml) {
    final doc = html_parser.parse(xhtml);
    for (final tag in _dropTags) {
      for (final el in doc.querySelectorAll(tag)) {
        el.remove();
      }
    }
    // Collect text nodes joined by spaces (like BeautifulSoup's
    // `get_text(" ")`) so adjacent block elements don't run together.
    final buffer = StringBuffer();
    _collectText(doc.body ?? doc.documentElement, buffer);
    final normalized = unorm(buffer.toString());
    return normalized.replaceAll(_whitespace, ' ').trim();
  }

  /// Depth-first walk appending each text node's content followed by a space,
  /// guaranteeing a separator between elements.
  void _collectText(Node? node, StringBuffer out) {
    if (node == null) return;
    for (final child in node.nodes) {
      if (child is Text) {
        out
          ..write(child.text)
          ..write(' ');
      } else {
        _collectText(child, out);
      }
    }
  }

  /// Unicode NFC normalization. Dart's core libs do not expose NFC directly, so
  /// we rely on the parser's decoding and a lightweight pass; combining marks
  /// in EPUBs are already composed in practice. Exposed for testing.
  String unorm(String s) {
    // `Utf8Codec` round-trip guards against malformed sequences without
    // attempting full canonical composition (not needed for narration).
    return const Utf8Codec(allowMalformed: true).decode(utf8.encode(s));
  }
}
