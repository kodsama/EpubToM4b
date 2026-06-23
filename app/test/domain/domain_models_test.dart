import 'package:audiobook_studio/domain/book.dart';
import 'package:audiobook_studio/domain/conversion_options.dart';
import 'package:audiobook_studio/domain/progress.dart';
import 'package:flutter_test/flutter_test.dart';

Book _book() => Book(
      title: 'Le Titre',
      author: 'Auteur',
      languageCode: 'fr',
      chapters: const [
        Chapter(index: 0, title: 'Un', text: 'abcde'), // 5 chars
        Chapter(index: 1, title: 'Deux', text: 'éàü'), // 3 runes
      ],
    );

void main() {
  group('Chapter.charCount', () {
    test('counts unicode code points, not UTF-16 units', () {
      const c = Chapter(index: 0, title: 't', text: 'éàü');
      expect(c.charCount, 3);
    });
  });

  group('Book.totalChars', () {
    test('sums chapter char counts', () {
      expect(_book().totalChars, 8);
    });
  });

  group('ConversionOptions.defaults', () {
    test('selects Piper, book language, natural speed, all chapters', () {
      final o = ConversionOptions.defaults(_book(),
          outputPath: '/out/book.m4b', workDir: '/tmp/work');
      expect(o.backend, TtsBackendKind.piper);
      expect(o.languageCode, 'fr');
      expect(o.speed, 1.0);
      expect(o.bitrate, '128k');
      expect(o.selectedChapterIndices, {0, 1});
      expect(o.outputPath, '/out/book.m4b');
    });

    test('copyWith replaces only the given field', () {
      final o = ConversionOptions.defaults(_book(),
          outputPath: '/out/book.m4b', workDir: '/tmp/work');
      final o2 = o.copyWith(backend: TtsBackendKind.openai, speed: 1.2);
      expect(o2.backend, TtsBackendKind.openai);
      expect(o2.speed, 1.2);
      expect(o2.languageCode, 'fr'); // unchanged
    });
  });

  group('TtsBackendKind.isCloud', () {
    test('classifies cloud vs local backends', () {
      expect(TtsBackendKind.openai.isCloud, isTrue);
      expect(TtsBackendKind.elevenlabs.isCloud, isTrue);
      expect(TtsBackendKind.piper.isCloud, isFalse);
      expect(TtsBackendKind.kokoro.isCloud, isFalse);
    });
  });

  group('ChapterProgress.fraction', () {
    test('is doneChars/totalChars, clamped', () {
      const p = ChapterProgress(
          index: 0, title: 't', totalChars: 100, doneChars: 25);
      expect(p.fraction, 0.25);
    });

    test('treats a zero-length chapter as complete', () {
      const p = ChapterProgress(index: 0, title: 't', totalChars: 0);
      expect(p.fraction, 1.0);
    });
  });

  group('ConversionProgress.globalFraction', () {
    test('is character-weighted across chapters', () {
      const p = ConversionProgress(chapters: [
        ChapterProgress(
            index: 0, title: 'a', totalChars: 100, doneChars: 100),
        ChapterProgress(index: 1, title: 'b', totalChars: 300, doneChars: 0),
      ]);
      // 100 done out of 400 total = 0.25
      expect(p.globalFraction, 0.25);
    });

    test('is 0 when there is no work', () {
      const p = ConversionProgress();
      expect(p.globalFraction, 0.0);
    });
  });
}
