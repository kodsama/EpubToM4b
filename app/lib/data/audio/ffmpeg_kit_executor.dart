/// In-process ffmpeg/ffprobe execution for Android & iOS via ffmpeg-kit.
///
/// iOS forbids spawning subprocesses and Android ships no ffmpeg binary, so the
/// desktop [ProcessFfmpegExecutor] cannot run there. This executor drives the
/// bundled ffmpeg-kit libraries instead, exposing the same [FfmpegExecutor] API
/// the conversion pipeline already depends on.
library;

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';

import 'ffmpeg_service.dart';

/// [FfmpegExecutor] backed by the in-process ffmpeg-kit engine (mobile only).
class FfmpegKitExecutor implements FfmpegExecutor {
  @override
  Future<void> run(List<String> args) async {
    final session = await FFmpegKit.executeWithArguments(args);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      final logs = await session.getAllLogsAsString();
      throw Exception(
        'ffmpeg failed (rc=${rc?.getValue()}): ${logs ?? '<no output>'}',
      );
    }
  }

  @override
  Future<int> durationMs(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final duration = session.getMediaInformation()?.getDuration();
    if (duration == null) {
      throw Exception('ffprobe could not read the duration of $path');
    }
    return (double.parse(duration) * 1000).round();
  }
}
