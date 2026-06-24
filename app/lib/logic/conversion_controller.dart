/// Orchestrates a full EPUB→M4B run and publishes progress.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/audio/ffmpeg_service.dart';
import '../data/text/text_chunker.dart';
import '../data/tts/tts_backend.dart';
import '../domain/book.dart';
import '../domain/conversion_options.dart';
import '../domain/progress.dart';
import 'log_controller.dart';

/// Drives the conversion pipeline chapter-by-chunk and exposes a live
/// [ConversionProgress] via [ChangeNotifier].
///
/// The pipeline is intentionally composed of small steps:
/// `_initProgress` → per chapter `_renderChapter` (`chunk` → `synth*` →
/// `concat`) → `_assemble`. Each step updates progress and is independently
/// reasoned about. Failures are isolated per chapter; cancellation is
/// cooperative (checked between chunks and chapters).
class ConversionController extends ChangeNotifier {
  final TextChunker _chunker;
  final LogController _log;

  ConversionController({TextChunker? chunker, required LogController log})
      : _chunker = chunker ?? TextChunker(),
        _log = log;

  ConversionProgress _progress = const ConversionProgress();

  /// Current progress snapshot.
  ConversionProgress get progress => _progress;

  bool _cancelled = false;

  /// Requests cancellation; the run stops before the next chunk/chapter.
  void cancel() {
    _cancelled = true;
    _log.warn('Cancellation requested');
  }

  /// Puts the progress view into an error state with [message], for failures
  /// that happen before/around a run (e.g. the backend can't be constructed).
  void markError(String message) {
    _setPhase(ConvPhase.error, message: message);
  }

  /// Runs the conversion for [book] with [options], using [backend] for speech
  /// and [ffmpeg] for assembly. Emits progress throughout; returns when the
  /// `.m4b` is written, the run is cancelled, or assembly is skipped because
  /// every selected chapter failed.
  Future<void> run(
    Book book,
    ConversionOptions options, {
    required TtsBackend backend,
    required FfmpegService ffmpeg,
  }) async {
    _cancelled = false;
    final selected = book.chapters
        .where((c) => options.selectedChapterIndices.contains(c.index))
        .toList();
    _initProgress(selected);
    Directory(options.workDir).createSync(recursive: true);

    final renderedChapters = <Chapter>[];
    final renderedWavs = <String>[];

    for (final chapter in selected) {
      if (_cancelled) {
        _setPhase(ConvPhase.idle, message: 'Cancelled');
        return;
      }
      final wav = await _renderChapter(chapter, options, backend, ffmpeg);
      if (wav != null) {
        renderedChapters.add(chapter);
        renderedWavs.add(wav);
      }
    }

    if (_cancelled) {
      _setPhase(ConvPhase.idle, message: 'Cancelled');
      return;
    }
    if (renderedWavs.isEmpty) {
      _setPhase(ConvPhase.error, message: 'No chapters were rendered');
      return;
    }

    await _assemble(book, renderedChapters, renderedWavs, options, backend, ffmpeg);
  }

  /// Renders one chapter to a WAV, returning its path or `null` on failure.
  Future<String?> _renderChapter(
    Chapter chapter,
    ConversionOptions options,
    TtsBackend backend,
    FfmpegService ffmpeg,
  ) async {
    final chapterWav =
        p.join(options.workDir, 'chapter_${chapter.index.toString().padLeft(4, '0')}.wav');

    // Resume: a finished chapter WAV is reused as-is.
    if (File(chapterWav).existsSync()) {
      _log.info('Chapter ${chapter.index + 1} cached, skipping synthesis');
      _updateChapter(chapter.index,
          doneChars: chapter.charCount, status: ChapterStatus.done);
      return chapterWav;
    }

    try {
      _updateChapter(chapter.index, status: ChapterStatus.synthesizing);
      final chunks = _chunker.chunk(chapter.text,
          maxChars: backend.maxChars, languageCode: options.languageCode);
      _log.info(
          'Chapter ${chapter.index + 1}: ${chapter.charCount} chars, ${chunks.length} chunks');

      final chunkWavs = <String>[];
      var done = 0;
      for (var i = 0; i < chunks.length; i++) {
        if (_cancelled) return null;
        final chunkWav = p.join(options.workDir,
            'chapter_${chapter.index.toString().padLeft(4, '0')}_chunk_${i.toString().padLeft(4, '0')}.wav');
        if (!File(chunkWav).existsSync()) {
          await backend.synth(chunks[i], chunkWav);
        }
        chunkWavs.add(chunkWav);
        done += chunks[i].runes.length;
        _updateChapter(chapter.index, doneChars: done);
      }

      _updateChapter(chapter.index, status: ChapterStatus.assembling);
      await ffmpeg.concatToChapterWav(chunkWavs, chapterWav, backend.sampleRate);
      for (final cw in chunkWavs) {
        try {
          File(cw).deleteSync();
        } on FileSystemException {
          // Non-fatal: leftover chunk files don't affect the output.
        }
      }
      _updateChapter(chapter.index,
          doneChars: chapter.charCount, status: ChapterStatus.done);
      return chapterWav;
    } catch (e) {
      _log.error('Chapter ${chapter.index + 1} failed: $e');
      _updateChapter(chapter.index,
          status: ChapterStatus.error, error: e.toString());
      return null;
    }
  }

  /// Final assembly: resolves the cover then muxes the `.m4b`.
  Future<void> _assemble(
    Book book,
    List<Chapter> chapters,
    List<String> wavs,
    ConversionOptions options,
    TtsBackend backend,
    FfmpegService ffmpeg,
  ) async {
    _setPhase(ConvPhase.assembling, message: 'Assembling audiobook');
    try {
      final coverPath = await _resolveCover(book, options);
      await ffmpeg.assembleM4b(book, chapters, wavs, options,
          coverPath: coverPath, sampleRate: backend.sampleRate);
      _setPhase(ConvPhase.done, message: 'Done → ${options.outputPath}');
      _log.info('Done → ${options.outputPath}');
    } catch (e) {
      _log.error('Assembly failed: $e');
      _setPhase(ConvPhase.error, message: 'Assembly failed: $e');
    }
  }

  /// Returns the cover path to embed: the user override, else the EPUB's own
  /// cover written to the work dir, else `null`.
  Future<String?> _resolveCover(Book book, ConversionOptions options) async {
    if (options.coverOverridePath != null) return options.coverOverridePath;
    if (!book.hasCover) return null;
    final ext = (book.coverContentType ?? '').contains('png') ? 'png' : 'jpg';
    final path = p.join(options.workDir, 'cover.$ext');
    await File(path).writeAsBytes(book.coverBytes!);
    return path;
  }

  // --- progress helpers ---

  void _initProgress(List<Chapter> selected) {
    _progress = ConversionProgress(
      phase: ConvPhase.synthesizing,
      chapters: [
        for (final c in selected)
          ChapterProgress(index: c.index, title: c.title, totalChars: c.charCount),
      ],
      message: 'Starting',
    );
    notifyListeners();
  }

  void _setPhase(ConvPhase phase, {String? message}) {
    _progress = _progress.copyWith(phase: phase, message: message);
    notifyListeners();
  }

  void _updateChapter(int index,
      {int? doneChars, ChapterStatus? status, String? error}) {
    final updated = [
      for (final c in _progress.chapters)
        if (c.index == index)
          c.copyWith(doneChars: doneChars, status: status, error: error)
        else
          c,
    ];
    _progress = _progress.copyWith(chapters: updated);
    notifyListeners();
  }
}
