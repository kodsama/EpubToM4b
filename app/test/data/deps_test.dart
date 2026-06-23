import 'package:audiobook_studio/data/deps/dependency_checker.dart';
import 'package:audiobook_studio/data/deps/dependency_installer.dart';
import 'package:audiobook_studio/data/process_runner.dart';
import 'package:audiobook_studio/domain/conversion_options.dart';
import 'package:audiobook_studio/domain/dependency.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripts canned responses keyed by the executable being run.
class ScriptedRunner extends ProcessRunner {
  final Map<String, ProcessRunResult> responses;
  final List<String> streamed = [];
  String? streamedExe;
  List<String>? streamedArgs;

  ScriptedRunner(this.responses);

  @override
  Future<ProcessRunResult> run(String e, List<String> a, {String? stdinText}) async {
    // Key by exe + first arg so `which ffmpeg` and `ffmpeg -version` differ.
    final key = '$e ${a.isNotEmpty ? a.first : ''}'.trim();
    return responses[key] ?? responses[e] ?? const ProcessRunResult(1, '', '');
  }

  @override
  Stream<String> stream(String e, List<String> a, {String? stdinText}) {
    streamedExe = e;
    streamedArgs = a;
    return Stream.fromIterable(['installing...', 'done']);
  }
}

void main() {
  group('DependencyChecker.requiredFor', () {
    final checker = DependencyChecker(ScriptedRunner({}));
    test('cloud backends need only ffmpeg + ffprobe', () {
      expect(checker.requiredFor(TtsBackendKind.openai),
          [DependencyKind.ffmpeg, DependencyKind.ffprobe]);
    });
    test('piper adds the binary and a voice', () {
      expect(checker.requiredFor(TtsBackendKind.piper), [
        DependencyKind.ffmpeg,
        DependencyKind.ffprobe,
        DependencyKind.piper,
        DependencyKind.piperVoice,
      ]);
    });
    test('kokoro adds espeak-ng and its model', () {
      expect(checker.requiredFor(TtsBackendKind.kokoro), [
        DependencyKind.ffmpeg,
        DependencyKind.ffprobe,
        DependencyKind.espeakNg,
        DependencyKind.kokoroModel,
      ]);
    });
  });

  group('DependencyChecker.check', () {
    test('reports missing when which exits non-zero', () async {
      final checker = DependencyChecker(ScriptedRunner({
        'which ffmpeg': const ProcessRunResult(1, '', 'not found'),
      }));
      final statuses = await checker.check(TtsBackendKind.openai, os: HostOs.macos);
      final ffmpeg = statuses.firstWhere((s) => s.kind == DependencyKind.ffmpeg);
      expect(ffmpeg.found, isFalse);
      expect(ffmpeg.installHint, 'brew install ffmpeg');
    });

    test('reports present with location + version when found', () async {
      final checker = DependencyChecker(ScriptedRunner({
        'which ffmpeg': const ProcessRunResult(0, '/opt/homebrew/bin/ffmpeg\n', ''),
        'ffmpeg -version': const ProcessRunResult(0, 'ffmpeg version 7.1\n...', ''),
        'which ffprobe': const ProcessRunResult(0, '/opt/homebrew/bin/ffprobe\n', ''),
        'ffprobe -version': const ProcessRunResult(0, 'ffprobe version 7.1\n', ''),
      }));
      final statuses = await checker.check(TtsBackendKind.openai, os: HostOs.macos);
      final ffmpeg = statuses.firstWhere((s) => s.kind == DependencyKind.ffmpeg);
      expect(ffmpeg.found, isTrue);
      expect(ffmpeg.location, '/opt/homebrew/bin/ffmpeg');
      expect(ffmpeg.version, 'ffmpeg version 7.1');
    });
  });

  group('DependencyInstaller', () {
    test('Mac builds a brew install command and streams output', () async {
      final runner = ScriptedRunner({});
      final installer = DependencyInstaller.forOs(HostOs.macos, runner);
      final lines = await installer
          .install([DependencyKind.ffmpeg, DependencyKind.espeakNg]).toList();

      expect(runner.streamedExe, 'brew');
      expect(runner.streamedArgs, ['install', 'ffmpeg', 'espeak-ng']);
      expect(lines, contains('installing...'));
    });

    test('Linux builds an apt-get command', () {
      final (exe, args) =
          LinuxInstaller(ScriptedRunner({})).installCommand(['ffmpeg']);
      expect(exe, 'sudo');
      expect(args, ['apt-get', 'install', '-y', 'ffmpeg']);
    });

    test('Windows maps packages to winget ids', () {
      final (exe, args) = WindowsInstaller(ScriptedRunner({}))
          .installCommand(['ffmpeg', 'espeak-ng']);
      expect(exe, 'winget');
      expect(args, containsAll(['Gyan.FFmpeg', 'eSpeak-NG.eSpeak-NG']));
    });

    test('download-only deps skip the package manager', () async {
      final runner = ScriptedRunner({});
      final installer = DependencyInstaller.forOs(HostOs.macos, runner);
      final lines = await installer.install([DependencyKind.piper]).toList();
      expect(lines.any((l) => l.contains('downloader')), isTrue);
      expect(runner.streamedExe, isNull); // brew never invoked
    });
  });
}
