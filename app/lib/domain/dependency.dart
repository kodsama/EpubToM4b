/// Models describing external dependencies the app needs and their state.
library;

/// Host operating systems the installer logic branches on. Kept separate from
/// `dart:io.Platform` so tests can drive each branch deterministically.
enum HostOs { macos, linux, windows }

/// An external tool/model the app relies on for a given backend.
enum DependencyKind {
  /// Audio encoder / muxer (all backends).
  ffmpeg,

  /// Media probe used for chapter durations (all backends).
  ffprobe,

  /// Piper TTS binary.
  piper,

  /// A Piper `.onnx` voice for the selected language.
  piperVoice,

  /// Phonemizer used by Kokoro.
  espeakNg,

  /// Kokoro ONNX model + voice pack.
  kokoroModel,
}

/// Whether a [DependencyKind] is a system package (installable via the OS
/// package manager) or a downloadable asset (model/voice fetched in-app).
extension DependencyKindInfo on DependencyKind {
  /// Short human label.
  String get label => switch (this) {
        DependencyKind.ffmpeg => 'ffmpeg',
        DependencyKind.ffprobe => 'ffprobe',
        DependencyKind.piper => 'piper',
        DependencyKind.piperVoice => 'Piper voice',
        DependencyKind.espeakNg => 'espeak-ng',
        DependencyKind.kokoroModel => 'Kokoro model',
      };

  /// True when this is installed by the OS package manager (vs. downloaded).
  bool get isSystemPackage => switch (this) {
        DependencyKind.ffmpeg ||
        DependencyKind.ffprobe ||
        DependencyKind.piper ||
        DependencyKind.espeakNg =>
          true,
        DependencyKind.piperVoice || DependencyKind.kokoroModel => false,
      };
}

/// The resolved state of one dependency on this machine.
class DependencyStatus {
  /// Which dependency this describes.
  final DependencyKind kind;

  /// Whether it was found.
  final bool found;

  /// Detected version string, when available.
  final String? version;

  /// Resolved path/location, when found.
  final String? location;

  /// A short hint shown when missing (e.g. the install command).
  final String? installHint;

  const DependencyStatus({
    required this.kind,
    required this.found,
    this.version,
    this.location,
    this.installHint,
  });

  @override
  String toString() =>
      'DependencyStatus(${kind.label}, found=$found, ${version ?? '-'})';
}
