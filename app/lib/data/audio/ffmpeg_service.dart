/// All ffmpeg/ffprobe invocations: chapter concat, durations, and final m4b.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/book.dart';
import '../../domain/conversion_options.dart';
import '../process_runner.dart';

/// A chapter WAV paired with its measured duration, used to build chapter
/// markers with correct cumulative timestamps.
typedef ChapterTiming = ({Chapter chapter, int durationMs});

/// The execution seam for ffmpeg/ffprobe.
///
/// Desktop (and the CLI) run the system binaries via a [ProcessRunner];
/// Android/iOS swap in an in-process engine (ffmpeg-kit) because spawning a
/// subprocess is forbidden on iOS and unavailable on Android.
abstract class FfmpegExecutor {
  /// Runs ffmpeg with [args]; throws on a non-zero/failed result.
  Future<void> run(List<String> args);

  /// Returns the media duration of [path] in milliseconds (ffprobe).
  Future<int> durationMs(String path);
}

/// Default [FfmpegExecutor] backed by the system `ffmpeg`/`ffprobe` binaries.
class ProcessFfmpegExecutor implements FfmpegExecutor {
  final ProcessRunner _runner;

  /// Name/path of the ffmpeg binary.
  final String ffmpeg;

  /// Name/path of the ffprobe binary.
  final String ffprobe;

  ProcessFfmpegExecutor(
    this._runner, {
    this.ffmpeg = 'ffmpeg',
    this.ffprobe = 'ffprobe',
  });

  @override
  Future<void> run(List<String> args) async {
    await _runner.checked(ffmpeg, args);
  }

  @override
  Future<int> durationMs(String path) async {
    final r = await _runner.checked(ffprobe, [
      '-v', 'error',
      '-show_entries', 'format=duration',
      '-of', 'default=noprint_wrappers=1:nokey=1',
      path,
    ]);
    return (double.parse(r.stdout.trim()) * 1000).round();
  }
}

/// Wraps ffmpeg/ffprobe. Pure string building (ffmetadata) is separated from
/// execution so it can be unit-tested without ffmpeg, and execution itself is
/// delegated to a pluggable [FfmpegExecutor] so the same pipeline runs on
/// desktop (system binaries) and mobile (in-process ffmpeg-kit).
class FfmpegService {
  final FfmpegExecutor _executor;

  /// Builds a service. By default execution uses the system `ffmpeg`/`ffprobe`
  /// binaries via [runner] (desktop/CLI); pass [executor] to override (mobile).
  FfmpegService(
    ProcessRunner runner, {
    String ffmpeg = 'ffmpeg',
    String ffprobe = 'ffprobe',
    FfmpegExecutor? executor,
  }) : _executor = executor ??
            ProcessFfmpegExecutor(runner, ffmpeg: ffmpeg, ffprobe: ffprobe);

  /// Merges chunk WAVs into one mono chapter WAV at [sampleRate]. A single
  /// input is simply re-encoded; multiple inputs are joined with the concat
  /// filter (ported from `concat_to_chapter_wav`).
  Future<void> concatToChapterWav(
    List<String> chunkWavs,
    String outWav,
    int sampleRate,
  ) async {
    if (chunkWavs.isEmpty) {
      throw ArgumentError('concatToChapterWav requires at least one input');
    }
    if (chunkWavs.length == 1) {
      await _executor.run([
        '-y', '-i', chunkWavs.single,
        '-ar', '$sampleRate', '-ac', '1', outWav,
      ]);
      return;
    }
    final inputs = <String>[];
    for (final w in chunkWavs) {
      inputs..add('-i')..add(w);
    }
    final streams =
        List.generate(chunkWavs.length, (i) => '[$i:a]').join();
    final filter = '${streams}concat=n=${chunkWavs.length}:v=0:a=1[a]';
    await _executor.run([
      '-y', ...inputs,
      '-filter_complex', filter,
      '-map', '[a]', '-ar', '$sampleRate', '-ac', '1', outWav,
    ]);
  }

  /// Returns the duration of [wavPath] in milliseconds via ffprobe.
  Future<int> wavDurationMs(String wavPath) => _executor.durationMs(wavPath);

  /// Escapes a value for an ffmetadata file (`=`, `;`, `#`, `\`, newline).
  static String escapeMeta(String s) =>
      s.replaceAllMapped(RegExp(r'([=;#\\\n])'), (m) => '\\${m[1]}');

  /// Builds the ffmetadata document: global tags plus one `[CHAPTER]` block per
  /// chapter with cumulative START/END in milliseconds (ported from
  /// `build_ffmetadata`).
  String buildFfMetadata(Book book, List<ChapterTiming> timings) {
    final lines = <String>[
      ';FFMETADATA1',
      'title=${escapeMeta(book.title)}',
      'artist=${escapeMeta(book.author)}',
      'album_artist=${escapeMeta(book.author)}',
      'album=${escapeMeta(book.title)}',
      'genre=Audiobook',
      'language=${escapeMeta(book.languageCode)}',
    ];
    var start = 0;
    for (final t in timings) {
      final end = start + t.durationMs;
      lines.addAll([
        '[CHAPTER]',
        'TIMEBASE=1/1000',
        'START=$start',
        'END=$end',
        'title=${escapeMeta(t.chapter.title)}',
      ]);
      start = end;
    }
    return '${lines.join('\n')}\n';
  }

  /// Assembles the final `.m4b` from per-chapter WAVs: AAC encode, chapter
  /// markers, optional cover art, tags, and `+faststart` (ported from
  /// `assemble_m4b`). [coverPath] overrides/embeds a cover when provided.
  /// [chapters] must align 1:1 with [chapterWavs] (the chapters actually
  /// rendered, which may be a user-selected subset of the book).
  Future<void> assembleM4b(
    Book book,
    List<Chapter> chapters,
    List<String> chapterWavs,
    ConversionOptions options, {
    String? coverPath,
    required int sampleRate,
  }) async {
    final workDir = options.workDir;
    final listFile = p.join(workDir, 'concat.txt');
    final metaFile = p.join(workDir, 'ffmeta.txt');

    await File(listFile).writeAsString(
      chapterWavs
          .map((w) => "file '${p.absolute(w)}'\n")
          .join(),
    );

    final timings = <ChapterTiming>[];
    for (var i = 0; i < chapterWavs.length; i++) {
      final dur = await wavDurationMs(chapterWavs[i]);
      timings.add((chapter: chapters[i], durationMs: dur));
    }
    await File(metaFile).writeAsString(buildFfMetadata(book, timings));

    final args = <String>[
      '-y',
      '-f', 'concat', '-safe', '0', '-i', listFile,
      '-i', metaFile,
      if (coverPath != null) ...['-i', coverPath],
      '-map', '0:a',
      if (coverPath != null) ...['-map', '2:v'],
      '-map_metadata', '1', '-map_chapters', '1',
      '-c:a', 'aac', '-b:a', options.bitrate, '-ar', '$sampleRate', '-ac', '1',
      if (coverPath != null) ...['-c:v', 'mjpeg', '-disposition:v', 'attached_pic'],
      '-movflags', '+faststart',
      options.outputPath,
    ];
    await _executor.run(args);
  }
}
