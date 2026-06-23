import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:audiobook_studio/data/epub/content_cleaner.dart';
import 'package:audiobook_studio/data/epub/epub_parser.dart';
import 'package:audiobook_studio/data/text/text_chunker.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a minimal but valid EPUB in memory: container, OPF (title/author/
/// language + cover), two chapter documents, and a cover image.
Uint8List _fixtureEpub() {
  final archive = Archive();
  void add(String name, String content) =>
      archive.addFile(ArchiveFile(name, content.length, utf8.encode(content)));

  add('META-INF/container.xml', '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''');

  add('OEBPS/content.opf', '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Mon Livre</dc:title>
    <dc:creator>Jean Auteur</dc:creator>
    <dc:language>fr-FR</dc:language>
    <meta name="cover" content="cover-img"/>
  </metadata>
  <manifest>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml"/>
    <item id="cover-img" href="images/cover.jpg" media-type="image/jpeg"/>
  </manifest>
  <spine>
    <itemref idref="nav"/>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>''');

  add('OEBPS/ch1.xhtml', '''
<html xmlns="http://www.w3.org/1999/xhtml"><body>
  <h1>Premier Chapitre</h1>
  <p>Bonjour le monde. <script>evil()</script> Ceci est un test.</p>
  <p>Une   deuxième    phrase ici.</p>
</body></html>''');

  add('OEBPS/ch2.xhtml', '''
<html xmlns="http://www.w3.org/1999/xhtml"><body>
  <h2>Deuxième Chapitre</h2>
  <p>Le contenu du deuxième chapitre est suffisamment long pour compter.</p>
</body></html>''');

  // nav is in the spine but must be skipped by name.
  add('OEBPS/nav.xhtml', '''
<html xmlns="http://www.w3.org/1999/xhtml"><body><nav>Table des matières
with plenty of text so it would otherwise pass the length filter.</nav></body></html>''');

  // A tiny fake JPEG (content irrelevant to parsing).
  archive.addFile(ArchiveFile(
      'OEBPS/images/cover.jpg', 4, Uint8List.fromList([255, 216, 255, 217])));

  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  group('ContentCleaner', () {
    final cleaner = ContentCleaner();

    test('drops scripts and collapses whitespace', () {
      const xhtml =
          '<html><body><p>Hello <script>bad()</script> world.</p>'
          '<p>Second    line.</p></body></html>';
      expect(cleaner.toText(xhtml), 'Hello world. Second line.');
    });

    test('removes tables and figures', () {
      const xhtml = '<html><body><p>Keep me.</p>'
          '<table><tr><td>drop</td></tr></table>'
          '<figure>caption</figure></body></html>';
      expect(cleaner.toText(xhtml), 'Keep me.');
    });
  });

  group('TextChunker', () {
    final chunker = TextChunker();

    test('keeps chunks within maxChars and groups sentences', () {
      final chunks = chunker.chunk(
        'Phrase une. Phrase deux. Phrase trois.',
        maxChars: 20,
      );
      expect(chunks, isNotEmpty);
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(20));
      }
      // Reassembled content preserves the words.
      expect(chunks.join(' ').replaceAll('  ', ' '),
          contains('Phrase trois.'));
    });

    test('hard-splits a single oversized sentence', () {
      final long = '${'a' * 5000}.';
      final chunks = chunker.chunk(long, maxChars: 1000);
      expect(chunks.length, greaterThanOrEqualTo(5));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(1000));
      }
    });
  });

  group('EpubParser', () {
    test('parses metadata, spine order, chapters, and cover', () {
      final book = EpubParser().parse(_fixtureEpub());

      expect(book.title, 'Mon Livre');
      expect(book.author, 'Jean Auteur');
      expect(book.languageCode, 'fr'); // normalized from fr-FR
      expect(book.hasCover, isTrue);
      expect(book.coverContentType, 'image/jpeg');

      // nav skipped by name -> exactly the two real chapters, in spine order.
      expect(book.chapters.length, 2);
      expect(book.chapters[0].title, 'Premier Chapitre');
      expect(book.chapters[1].title, 'Deuxième Chapitre');
      expect(book.chapters[0].index, 0);
      expect(book.chapters[0].text, contains('Bonjour le monde.'));
      expect(book.chapters[0].text, isNot(contains('evil')));
    });

    test('throws on an archive with no readable chapters', () {
      final empty = Archive()
        ..addFile(ArchiveFile('META-INF/container.xml', 1, utf8.encode('''
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="content.opf"/></rootfiles></container>''')))
        ..addFile(ArchiveFile('content.opf', 1, utf8.encode('''
<package xmlns="http://www.idpf.org/2007/opf"><manifest/><spine/></package>''')));
      final bytes = Uint8List.fromList(ZipEncoder().encode(empty)!);
      expect(() => EpubParser().parse(bytes), throwsFormatException);
    });
  });
}
