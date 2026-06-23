/// Installs missing system-package dependencies per platform.
library;

import '../../domain/dependency.dart';
import '../process_runner.dart';

/// Installs the OS-package dependencies (ffmpeg, espeak-ng) for a platform,
/// streaming command output. Download-only deps (piper, voices, models) are
/// reported as handled elsewhere rather than passed to the package manager.
abstract class DependencyInstaller {
  final ProcessRunner runner;

  DependencyInstaller(this.runner);

  /// The package-manager package name for a system dependency.
  static String packageName(DependencyKind kind) =>
      kind == DependencyKind.espeakNg ? 'espeak-ng' : 'ffmpeg';

  /// Builds the install command (executable + args) for the given system
  /// [packages]. Exposed for testing the command without executing it.
  (String, List<String>) installCommand(List<String> packages);

  /// Installs the system-package subset of [kinds], streaming output lines.
  /// Non-system kinds are announced and skipped (the downloader handles them).
  Stream<String> install(List<DependencyKind> kinds) async* {
    final system = kinds.where((k) => k.isSystemPackage).toList();
    final downloads = kinds.where((k) => !k.isSystemPackage).toList();
    for (final d in downloads) {
      yield '• ${d.label}: fetched by the in-app downloader (skipping package manager).';
    }
    if (system.isEmpty) {
      yield 'No system packages to install.';
      return;
    }
    final packages =
        system.map(DependencyInstaller.packageName).toSet().toList();
    final (exe, args) = installCommand(packages);
    yield '\$ $exe ${args.join(' ')}';
    yield* runner.stream(exe, args);
  }

  /// Returns the right installer for [os].
  factory DependencyInstaller.forOs(HostOs os, ProcessRunner runner) {
    return switch (os) {
      HostOs.macos => MacInstaller(runner),
      HostOs.linux => LinuxInstaller(runner),
      HostOs.windows => WindowsInstaller(runner),
    };
  }
}

/// Homebrew installer (`brew install ...`).
class MacInstaller extends DependencyInstaller {
  MacInstaller(super.runner);

  @override
  (String, List<String>) installCommand(List<String> packages) =>
      ('brew', ['install', ...packages]);
}

/// apt installer (`sudo apt-get install -y ...`).
class LinuxInstaller extends DependencyInstaller {
  LinuxInstaller(super.runner);

  @override
  (String, List<String>) installCommand(List<String> packages) =>
      ('sudo', ['apt-get', 'install', '-y', ...packages]);
}

/// winget installer (one package per invocation; the first is emitted here and
/// [install] streams the rest sequentially via the package manager).
class WindowsInstaller extends DependencyInstaller {
  WindowsInstaller(super.runner);

  /// Maps a generic package name to its winget id.
  static String wingetId(String pkg) =>
      pkg == 'espeak-ng' ? 'eSpeak-NG.eSpeak-NG' : 'Gyan.FFmpeg';

  @override
  (String, List<String>) installCommand(List<String> packages) => (
        'winget',
        [
          'install',
          '--accept-package-agreements',
          '--accept-source-agreements',
          ...packages.map(wingetId),
        ],
      );
}
