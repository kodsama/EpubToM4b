/// Probes the host for the system tools the app needs (ffmpeg/ffprobe).
library;

import '../../domain/conversion_options.dart';
import '../../domain/dependency.dart';
import '../process_runner.dart';

/// Locates ffmpeg/ffprobe via `which`/`where` and reports their status. Local
/// TTS models are handled by the in-app model downloader, not here.
class DependencyChecker {
  final ProcessRunner _runner;

  /// When true, ffmpeg/ffprobe are bundled in-process (mobile, ffmpeg-kit) and
  /// reported as present without probing the host — `which`/`where` would crash
  /// on iOS, where spawning subprocesses is forbidden.
  final bool bundled;

  DependencyChecker(this._runner, {this.bundled = false});

  /// Dependencies required to run [backend] — ffmpeg/ffprobe for every engine.
  List<DependencyKind> requiredFor(TtsBackendKind backend) =>
      const [DependencyKind.ffmpeg, DependencyKind.ffprobe];

  /// Probes ffmpeg/ffprobe on [os].
  Future<List<DependencyStatus>> check(
    TtsBackendKind backend, {
    required HostOs os,
  }) =>
      checkAll(os: os);

  /// Probes every system dependency. When [bundled] (mobile), reports them all
  /// as present since ffmpeg-kit ships them in-process.
  Future<List<DependencyStatus>> checkAll({required HostOs os}) async {
    if (bundled) {
      return [
        for (final kind in DependencyKind.values)
          DependencyStatus(kind: kind, found: true, location: 'bundled'),
      ];
    }
    final result = <DependencyStatus>[];
    for (final kind in DependencyKind.values) {
      result.add(await _probe(kind, os));
    }
    return result;
  }

  Future<DependencyStatus> _probe(DependencyKind kind, HostOs os) async {
    final bin = kind.binaryName;
    final locator = os == HostOs.windows ? 'where' : 'which';
    final located = await _runner.run(locator, [bin]);
    if (!located.ok || located.stdout.trim().isEmpty) {
      return DependencyStatus(
        kind: kind,
        found: false,
        installHint: _hint(os),
      );
    }
    final location = located.stdout.trim().split('\n').first.trim();
    return DependencyStatus(
      kind: kind,
      found: true,
      location: location,
      version: await _version(bin),
    );
  }

  Future<String?> _version(String bin) async {
    final r = await _runner.run(bin, ['-version']);
    if (!r.ok) return null;
    final first = r.stdout.split('\n').first.trim();
    return first.isEmpty ? null : first;
  }

  String _hint(HostOs os) => switch (os) {
        HostOs.macos => 'brew install ffmpeg',
        HostOs.linux => 'sudo apt-get install -y ffmpeg',
        HostOs.windows => 'winget install Gyan.FFmpeg',
      };
}
