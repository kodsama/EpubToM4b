/// Probes the host for the binaries a backend needs.
library;

import '../../domain/conversion_options.dart';
import '../../domain/dependency.dart';
import '../process_runner.dart';

/// Resolves which dependencies a given [TtsBackendKind] requires and whether
/// each is present on this machine, using `which`/`where` to locate binaries.
class DependencyChecker {
  final ProcessRunner _runner;

  DependencyChecker(this._runner);

  /// The dependencies required to run [backend]. ffmpeg/ffprobe are always
  /// needed; Piper adds the piper binary + a voice; Kokoro adds espeak-ng + its
  /// model; cloud backends need nothing local.
  List<DependencyKind> requiredFor(TtsBackendKind backend) => <DependencyKind>[
        DependencyKind.ffmpeg,
        DependencyKind.ffprobe,
        if (backend == TtsBackendKind.piper) ...[
          DependencyKind.piper,
          DependencyKind.piperVoice,
        ],
        if (backend == TtsBackendKind.kokoro) ...[
          DependencyKind.espeakNg,
          DependencyKind.kokoroModel,
        ],
      ];

  /// Probes every dependency required for [backend] on [os] and returns their
  /// resolved statuses (order matches [requiredFor]).
  Future<List<DependencyStatus>> check(
    TtsBackendKind backend, {
    required HostOs os,
  }) async {
    final result = <DependencyStatus>[];
    for (final kind in requiredFor(backend)) {
      result.add(await _probe(kind, os));
    }
    return result;
  }

  /// Probes a single dependency. Binary deps are located on `PATH`; download
  /// deps (voices/models) are reported missing here and handled by the
  /// downloader UI.
  Future<DependencyStatus> _probe(DependencyKind kind, HostOs os) async {
    final bin = kind.binaryName;
    if (bin == null) {
      return DependencyStatus(
        kind: kind,
        found: false,
        installHint: 'Downloaded in-app',
      );
    }
    final locator = os == HostOs.windows ? 'where' : 'which';
    final located = await _runner.run(locator, [bin]);
    if (!located.ok || located.stdout.trim().isEmpty) {
      return DependencyStatus(
        kind: kind,
        found: false,
        installHint: _hint(kind, os),
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

  /// Best-effort version string from `<bin> -version` (first line).
  Future<String?> _version(String bin) async {
    final r = await _runner.run(bin, ['-version']);
    if (!r.ok) return null;
    final first = r.stdout.split('\n').first.trim();
    return first.isEmpty ? null : first;
  }

  /// A short, actionable hint for a missing dependency.
  String _hint(DependencyKind kind, HostOs os) {
    if (kind == DependencyKind.piper) {
      return 'Install the piper binary, or pick a cloud engine';
    }
    if (!kind.isSystemPackage) return 'Fetched automatically';
    final pkg = kind == DependencyKind.espeakNg ? 'espeak-ng' : 'ffmpeg';
    return switch (os) {
      HostOs.macos => 'brew install $pkg',
      HostOs.linux => 'sudo apt-get install -y $pkg',
      HostOs.windows => 'winget install $pkg',
    };
  }
}
