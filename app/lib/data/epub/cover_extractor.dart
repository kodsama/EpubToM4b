/// Extracts the best available cover image from an EPUB archive.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'opf_reader.dart';

/// The bytes and MIME type of an extracted cover image.
typedef CoverImage = ({Uint8List bytes, String contentType});

/// Picks a cover image: the OPF-declared cover if present, otherwise the
/// highest-scoring image whose archive name contains "cover" (mirrors the
/// fallback heuristic in `epub_to_m4b.py` `_extract_cover`).
class CoverExtractor {
  /// Returns the cover image, or `null` if the archive has no usable image.
  CoverImage? extract(Archive archive, OpfData opf) {
    // 1) Prefer the explicitly declared cover.
    if (opf.coverHref != null) {
      final found = _read(archive, opf.coverHref!);
      if (found != null) {
        return (bytes: found, contentType: opf.mediaTypes[opf.coverHref!] ?? _guess(opf.coverHref!));
      }
    }

    // 2) Fall back to the best image candidate by name.
    ArchiveFile? best;
    var bestScore = -1;
    for (final f in archive.files) {
      final name = f.name.toLowerCase();
      final media = opf.mediaTypes[f.name] ?? '';
      final isImage = media.startsWith('image/') ||
          name.endsWith('.jpg') ||
          name.endsWith('.jpeg') ||
          name.endsWith('.png');
      if (!isImage) continue;
      final score = name.contains('cover') ? 2 : 0;
      if (score > bestScore) {
        bestScore = score;
        best = f;
      }
    }
    if (best == null) return null;
    return (
      bytes: Uint8List.fromList(best.content as List<int>),
      contentType: opf.mediaTypes[best.name] ?? _guess(best.name),
    );
  }

  Uint8List? _read(Archive archive, String path) {
    for (final f in archive.files) {
      if (f.name == path) return Uint8List.fromList(f.content as List<int>);
    }
    return null;
  }

  String _guess(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }
}
