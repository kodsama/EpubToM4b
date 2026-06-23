/// Locates and parses an EPUB's OPF package document.
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// Structured result of reading the OPF: metadata, reading order, and the
/// information needed to locate the cover image.
class OpfData {
  /// `dc:title`, or empty if absent.
  final String title;

  /// `dc:creator`, or empty if absent.
  final String author;

  /// `dc:language` (ISO 639-1), defaulting to `en`.
  final String languageCode;

  /// Archive paths of spine documents, in reading order.
  final List<String> spineHrefs;

  /// Map of manifest archive path → media type (e.g. `image/jpeg`).
  final Map<String, String> mediaTypes;

  /// Archive path of the declared cover image, if the OPF identified one.
  final String? coverHref;

  const OpfData({
    required this.title,
    required this.author,
    required this.languageCode,
    required this.spineHrefs,
    required this.mediaTypes,
    this.coverHref,
  });
}

/// Reads the OPF package document from an in-memory EPUB [Archive].
class OpfReader {
  /// Parses the OPF and returns structured [OpfData].
  ///
  /// Throws [FormatException] if the archive is not a valid EPUB (missing
  /// container or package document).
  OpfData read(Archive archive) {
    final opfPath = _findOpfPath(archive);
    final opfDir = p.url.dirname(opfPath);
    final opfXml = _readString(archive, opfPath);
    final doc = XmlDocument.parse(opfXml);
    final pkg = doc.rootElement;

    String dc(String name) {
      final el = pkg
          .findAllElements(name, namespaceUri: '*')
          .where((e) => e.qualifiedName.endsWith(name))
          .firstOrNull;
      return el?.innerText.trim() ?? '';
    }

    // Resolve a manifest href (relative to the OPF dir) to an archive path.
    String resolve(String href) =>
        p.url.normalize(p.url.join(opfDir, href));

    // Manifest: id -> archive path, and archive path -> media type.
    final idToHref = <String, String>{};
    final mediaTypes = <String, String>{};
    String? coverIdHref;
    for (final item in pkg.findAllElements('item', namespaceUri: '*')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      final media = item.getAttribute('media-type') ?? '';
      if (id == null || href == null) continue;
      final path = resolve(href);
      idToHref[id] = path;
      mediaTypes[path] = media;
      // EPUB3 cover marker.
      if ((item.getAttribute('properties') ?? '').contains('cover-image')) {
        coverIdHref = path;
      }
    }

    // EPUB2 cover marker: <meta name="cover" content="cover-id"/>.
    if (coverIdHref == null) {
      for (final meta in pkg.findAllElements('meta', namespaceUri: '*')) {
        if (meta.getAttribute('name') == 'cover') {
          final id = meta.getAttribute('content');
          coverIdHref = id == null ? null : idToHref[id];
          break;
        }
      }
    }

    // Spine: ordered itemref -> manifest id -> archive path.
    final spine = <String>[];
    for (final ref in pkg.findAllElements('itemref', namespaceUri: '*')) {
      final idref = ref.getAttribute('idref');
      final path = idref == null ? null : idToHref[idref];
      if (path != null) spine.add(path);
    }

    final lang = dc('language');
    return OpfData(
      title: dc('title'),
      author: dc('creator'),
      languageCode: lang.isEmpty ? 'en' : lang.split('-').first.toLowerCase(),
      spineHrefs: spine,
      mediaTypes: mediaTypes,
      coverHref: coverIdHref,
    );
  }

  /// Finds the OPF path via `META-INF/container.xml`.
  String _findOpfPath(Archive archive) {
    final container = _readString(archive, 'META-INF/container.xml');
    final doc = XmlDocument.parse(container);
    final rootfile = doc.findAllElements('rootfile', namespaceUri: '*').firstOrNull;
    final fullPath = rootfile?.getAttribute('full-path');
    if (fullPath == null) {
      throw const FormatException('EPUB container.xml has no rootfile');
    }
    return fullPath;
  }

  /// Reads an archive entry as UTF-8 text, throwing if it is missing.
  String _readString(Archive archive, String path) {
    final file = archive.files.firstWhere(
      (f) => f.name == path,
      orElse: () => throw FormatException('EPUB missing entry: $path'),
    );
    return utf8.decode(file.content as List<int>, allowMalformed: true);
  }
}
