import 'dart:io';

import 'package:audiobook_studio/data/audio/ffmpeg_service.dart';
import 'package:audiobook_studio/data/process_runner.dart';
import 'package:audiobook_studio/data/tts/tts_backend.dart';
import 'package:audiobook_studio/domain/book.dart';
import 'package:audiobook_studio/domain/conversion_options.dart';
import 'package:audiobook_studio/domain/progress.dart';
import 'package:audiobook_studio/domain/voice.dart';
import 'package:audiobook_studio/logic/conversion_controller.dart';
import 'package:audiobook_studio/logic/log_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Records synth calls and writes a tiny placeholder WAV per chunk. Can be told
/// to throw for a specific chapter index (detected from the output filename).
class FakeTtsBackend extends TtsBackend {
  final List<String> synthTexts = [];
  final int? failChapterIndex;
  final void Function()? onFirstSynth;
  bool _firstFired = false;

  FakeTtsBackend({this.failChapterIndex, this.onFirstSynth});

  @override
  int get sampleRate => 22050;
  @override
  int get maxChars => 50;
  @override
  List<Language> get supportedLanguages => const [Language('fr', 'Français')];
  @override
  List<Voice> voicesFor(String languageCode) => const [];

  @override
  Future<void> synth(String text, String outWavPath) async {
    if (!_firstFired) {
      _firstFired = true;
      onFirstSynth?.call();
    }
    if (failChapterIndex != null &&
        outWavPath.contains('chapter_${failChapterIndex.toString().padLeft(4, '0')}_')) {
      throw Exception('synth boom');
    }
    synthTexts.add(text);
    File(outWavPath).writeAsBytesSync(const [0, 0]);
  }
}

/// Records ffmpeg calls and creates placeholder output files.
class FakeFfmpegService extends FfmpegService {
  int concatCalls = 0;
  int assembleCalls = 0;
  List<Chapter> assembledChapters = const [];

  FakeFfmpegService() : super(_NoopRunner());

  @override
  Future<void> concatToChapterWav(
      List<String> chunkWavs, String outWav, int sampleRate) async {
    concatCalls++;
    File(outWav).writeAsBytesSync(const [0, 0]);
  }

  @override
  Future<int> wavDurationMs(String wavPath) async => 1000;

  @override
  Future<void> assembleM4b(Book book, List<Chapter> chapters,
      List<String> chapterWavs, ConversionOptions options,
      {String? coverPath, required int sampleRate}) async {
    assembleCalls++;
    assembledChapters = chapters;
    File(options.outputPath).writeAsBytesSync(const [0]);
  }
}

class _NoopRunner extends ProcessRunner {
  @override
  Future<ProcessRunResult> run(String e, List<String> a, {String? stdinText}) async =>
      const ProcessRunResult(0, '', '');
  @override
  Stream<String> stream(String e, List<String> a, {String? stdinText}) =>
      const Stream.empty();
}

void main() {
  late Directory tmp;
  late LogController log;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('conv_test_');
    log = LogController();
  });
  tearDown(() {
    log.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Book book() => Book(
        title: 'T',
        author: 'A',
        languageCode: 'fr',
        chapters: const [
          Chapter(index: 0, title: 'One', text: 'Phrase une. Phrase deux.'),
          Chapter(index: 1, title: 'Two', text: 'Autre phrase ici.'),
        ],
      );

  ConversionOptions opts(Book b, {Set<int>? sel}) => ConversionOptions.defaults(
        b,
        outputPath: p.join(tmp.path, 'out.m4b'),
        workDir: p.join(tmp.path, 'work'),
      ).copyWith(selectedChapterIndices: sel);

  test('renders every chapter then assembles once', () async {
    final tts = FakeTtsBackend();
    final ff = FakeFfmpegService();
    final c = ConversionController(log: log);

    await c.run(book(), opts(book()), backend: tts, ffmpeg: ff);

    expect(ff.concatCalls, 2); // one concat per chapter
    expect(ff.assembleCalls, 1); // one final assembly
    expect(c.progress.phase, ConvPhase.done);
    expect(c.progress.chapters.every((ch) => ch.status == ChapterStatus.done),
        isTrue);
    expect(c.progress.globalFraction, 1.0);
    expect(File(p.join(tmp.path, 'out.m4b')).existsSync(), isTrue);
  });

  test('progress fraction is monotonically non-decreasing', () async {
    final c = ConversionController(log: log);
    final seen = <double>[];
    c.addListener(() => seen.add(c.progress.globalFraction));

    await c.run(book(), opts(book()), backend: FakeTtsBackend(), ffmpeg: FakeFfmpegService());

    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
    }
    expect(seen.last, 1.0);
  });

  test('resumes by skipping chapters whose WAV already exists', () async {
    final work = Directory(p.join(tmp.path, 'work'))..createSync(recursive: true);
    // Pre-create chapter 0's WAV.
    File(p.join(work.path, 'chapter_0000.wav')).writeAsBytesSync(const [0]);

    final tts = FakeTtsBackend();
    final c = ConversionController(log: log);
    await c.run(book(), opts(book()), backend: tts, ffmpeg: FakeFfmpegService());

    // Only chapter 1 should have been synthesized.
    expect(tts.synthTexts.join(' '), isNot(contains('Phrase une')));
    expect(tts.synthTexts.join(' '), contains('Autre phrase'));
    expect(c.progress.chapters[0].status, ChapterStatus.done);
  });

  test('isolates a failing chapter and still assembles the rest', () async {
    final ff = FakeFfmpegService();
    final c = ConversionController(log: log);
    await c.run(book(), opts(book()),
        backend: FakeTtsBackend(failChapterIndex: 0), ffmpeg: ff);

    expect(c.progress.chapters[0].status, ChapterStatus.error);
    expect(c.progress.chapters[1].status, ChapterStatus.done);
    expect(ff.assembleCalls, 1);
    expect(ff.assembledChapters.map((ch) => ch.index), [1]); // only the good one
    expect(c.progress.phase, ConvPhase.done);
  });

  test('honours a selected subset of chapters', () async {
    final ff = FakeFfmpegService();
    final c = ConversionController(log: log);
    await c.run(book(), opts(book(), sel: {1}), backend: FakeTtsBackend(), ffmpeg: ff);

    expect(c.progress.chapters.length, 1);
    expect(ff.assembledChapters.map((ch) => ch.index), [1]);
  });

  test('cancellation stops before assembly', () async {
    final ff = FakeFfmpegService();
    final c = ConversionController(log: log);
    // Cancel as soon as the first synth runs.
    final tts = FakeTtsBackend(onFirstSynth: () => c.cancel());

    await c.run(book(), opts(book()), backend: tts, ffmpeg: ff);

    expect(ff.assembleCalls, 0);
    expect(c.progress.phase, ConvPhase.idle);
  });

  group('FfmpegService.buildFfMetadata', () {
    test('emits cumulative chapter START/END blocks', () {
      final svc = FfmpegService(_NoopRunner());
      final b = book();
      final meta = svc.buildFfMetadata(b, [
        (chapter: b.chapters[0], durationMs: 1000),
        (chapter: b.chapters[1], durationMs: 2000),
      ]);
      expect(meta, contains('title=T'));
      expect(meta, contains('genre=Audiobook'));
      expect(meta, contains('START=0\nEND=1000'));
      expect(meta, contains('START=1000\nEND=3000')); // cumulative
    });

    test('escapes ffmetadata special characters', () {
      expect(FfmpegService.escapeMeta('a=b;c#d'), r'a\=b\;c\#d');
    });
  });
}
