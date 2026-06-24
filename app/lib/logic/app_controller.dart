/// The UI-facing application state machine.
///
/// Ties together parsing, options, dependency checks, and the conversion run
/// behind one [ChangeNotifier] the widgets observe. Deliberately free of any
/// Flutter widget or file-picker dependency (the UI hands it bytes/paths) so it
/// can be unit/widget-tested directly.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../data/audio/ffmpeg_service.dart';
import '../data/deps/dependency_checker.dart';
import '../data/deps/dependency_installer.dart';
import '../data/deps/kokoro_installer.dart';
import '../data/deps/piper_installer.dart';
import '../data/epub/epub_parser.dart';
import '../data/process_runner.dart';
import '../data/tts/backend_factory.dart';
import '../data/tts/voice_catalog.dart';
import '../domain/book.dart';
import '../domain/conversion_options.dart';
import '../domain/dependency.dart';
import '../domain/progress.dart';
import 'conversion_controller.dart';
import 'log_controller.dart';

/// Orchestrates the end-to-end UI workflow and exposes observable state.
class AppController extends ChangeNotifier {
  final EpubParser parser;
  final FfmpegService ffmpeg;
  final ProcessRunner runner;
  final http.Client httpClient;
  final DependencyChecker checker;
  final PiperInstaller piperInstaller;
  final KokoroInstaller kokoroInstaller;
  final LogController log;
  final ConversionController conversion;
  final HostOs os;
  final String modelsDir;

  AppController({
    required this.parser,
    required this.ffmpeg,
    required this.runner,
    required this.httpClient,
    required this.checker,
    required this.piperInstaller,
    required this.kokoroInstaller,
    required this.log,
    required this.conversion,
    required this.os,
    required this.modelsDir,
    bool checkOnStart = true,
  }) {
    conversion.addListener(notifyListeners);
    // Verify the toolkit immediately so step 1 is populated on launch.
    if (checkOnStart) unawaited(checkDeps());
  }

  Book? _book;
  ConversionOptions? _options;
  List<DependencyStatus> _deps = const [];
  bool _depsChecked = false;
  bool _installing = false;
  String? _parseError;

  /// The parsed book, or null before one is loaded.
  Book? get book => _book;

  /// Current conversion options (null before a book is loaded).
  ConversionOptions? get options => _options;

  /// Latest dependency statuses for the selected backend.
  List<DependencyStatus> get deps => _deps;

  /// Whether a dependency check has completed at least once.
  bool get depsChecked => _depsChecked;

  /// Whether an install is currently streaming.
  bool get installing => _installing;

  /// The last parse error message, if loading failed.
  String? get parseError => _parseError;

  /// Live conversion progress.
  ConversionProgress get progress => conversion.progress;

  /// Whether a conversion run is in flight.
  bool get isConverting =>
      progress.phase == ConvPhase.synthesizing ||
      progress.phase == ConvPhase.assembling;

  /// Missing dependencies among the current statuses.
  List<DependencyStatus> get missingDeps =>
      _deps.where((d) => !d.found).toList();

  /// Parses [bytes] from [sourcePath], derives default options, and checks deps.
  Future<void> loadBook(Uint8List bytes, String sourcePath) async {
    _parseError = null;
    try {
      final stem = p.basenameWithoutExtension(sourcePath);
      final book = parser.parse(bytes, fallbackTitle: stem);
      _book = book;
      // Probe the environment first so we can pre-select an engine that is
      // actually usable (local preferred over cloud).
      await checkDeps();
      final backend = preferredBackend();
      final dir = p.dirname(sourcePath);
      final safe = _safeName(book.title);
      _options = ConversionOptions.defaults(
        book,
        outputPath: p.join(dir, '$safe.m4b'),
        workDir: p.join(dir, '$safe.work'),
        voiceId: VoiceCatalog.defaultVoiceId(backend, book.languageCode),
      ).copyWith(backend: backend);
      log.info('Loaded "${book.title}" — ${book.chapters.length} chapters '
          '· engine: ${backend.label}');
      notifyListeners();
    } on Object catch (e) {
      _parseError = e.toString();
      log.error('Failed to parse EPUB: $e');
      notifyListeners();
    }
  }

  /// Replaces the options with [update] applied (no-op if no book loaded).
  void updateOptions(ConversionOptions Function(ConversionOptions) update) {
    final o = _options;
    if (o == null) return;
    _options = update(o);
    notifyListeners();
  }

  /// Switches backend and resets language/voice to that backend's defaults,
  /// then re-checks dependencies.
  Future<void> setBackend(TtsBackendKind backend) async {
    final o = _options;
    final b = _book;
    if (o == null || b == null) return;
    final langs = VoiceCatalog.languages(backend).map((l) => l.code).toList();
    final lang = langs.contains(b.languageCode)
        ? b.languageCode
        : (langs.isEmpty ? b.languageCode : langs.first);
    _options = o.copyWith(
      backend: backend,
      languageCode: lang,
      voiceId: VoiceCatalog.defaultVoiceId(backend, lang),
    );
    notifyListeners();
    await checkDeps();
  }

  /// Sets the narration language and resets the voice to its default.
  void setLanguage(String code) {
    final o = _options;
    if (o == null) return;
    _options = o.copyWith(
      languageCode: code,
      voiceId: VoiceCatalog.defaultVoiceId(o.backend, code),
    );
    notifyListeners();
  }

  /// Toggles whether [index] is included in the output.
  void toggleChapter(int index) {
    final o = _options;
    if (o == null) return;
    final next = {...o.selectedChapterIndices};
    next.contains(index) ? next.remove(index) : next.add(index);
    _options = o.copyWith(selectedChapterIndices: next);
    notifyListeners();
  }

  /// Probes every known dependency (across all engines) so the toolkit shows
  /// the full picture. Runs on launch and whenever the backend changes.
  Future<void> checkDeps() async {
    _deps = await checker.checkAll(os: os);
    _depsChecked = true;
    notifyListeners();
  }

  /// Status for a specific dependency kind, if probed.
  DependencyStatus? statusOf(DependencyKind kind) {
    for (final d in _deps) {
      if (d.kind == kind) return d;
    }
    return null;
  }

  /// Required dependencies (ffmpeg/ffprobe) that are still missing.
  List<DependencyStatus> get missingRequired =>
      _deps.where((d) => d.kind.isRequired && !d.found).toList();

  /// Whether the *core* tools (ffmpeg/ffprobe) are present. This gates choosing
  /// a book; engine-specific tools are handled per engine afterwards.
  bool get coreToolsReady => _depsChecked && missingRequired.isEmpty;

  /// Whether at least one TTS engine is actually usable right now: a local
  /// engine is installed, or a cloud engine has an API key entered. Used so the
  /// toolkit doesn't claim "Ready" when no engine can speak.
  bool get anyEngineReady => TtsBackendKind.values.any((k) {
        if (!backendAvailable(k)) return false;
        if (k.isCloud) {
          return (_options?.apiKeys[k.name] ?? '').trim().isNotEmpty;
        }
        return true;
      });

  /// Overall readiness shown as "Ready": core tools present *and* a usable
  /// engine exists.
  bool get environmentReady => coreToolsReady && anyEngineReady;

  /// Whether [backend] is installed/configured enough to be *selectable*.
  ///
  /// Cloud engines are always selectable (you configure them by entering an API
  /// key after selecting). Local engines require their tools to be present:
  /// Piper needs the piper binary; Kokoro needs espeak-ng and its model. This
  /// excludes the API-key check, which gates conversion (not selection).
  bool backendAvailable(TtsBackendKind backend) {
    if (backend.isCloud) return true;
    if (!_depsChecked) return false;
    if (backend == TtsBackendKind.piper) {
      // Needs the downloaded binary AND the chosen voice (defaulting to the
      // book's language when no options exist yet).
      if (!piperInstaller.isBinaryInstalled()) return false;
      final voiceId = _options?.voiceId ??
          VoiceCatalog.defaultVoiceId(
              TtsBackendKind.piper, _book?.languageCode ?? 'en');
      return piperInstaller.isVoiceInstalled(voiceId);
    }
    if (backend == TtsBackendKind.kokoro) {
      // Needs espeak-ng (for phonemes) and the downloaded model + voices.
      final espeak = statusOf(DependencyKind.espeakNg)?.found ?? false;
      return espeak && kokoroInstaller.isInstalled();
    }
    return true;
  }

  /// Whether Piper is selected but its binary/voice still need downloading.
  bool get needsPiperSetup {
    final o = _options;
    return o != null &&
        o.backend == TtsBackendKind.piper &&
        !backendAvailable(TtsBackendKind.piper);
  }

  bool _installingPiper = false;

  /// Whether a Piper download is in progress.
  bool get installingPiper => _installingPiper;

  /// Downloads the Piper binary and the selected voice (whatever is missing),
  /// streaming progress to the log, then re-checks dependencies.
  Future<void> setupPiper() async {
    final o = _options;
    if (o == null || _installingPiper) return;
    _installingPiper = true;
    notifyListeners();
    try {
      await for (final line in piperInstaller.ensureInstalled(o.voiceId)) {
        log.info(line);
      }
    } on Object catch (e) {
      log.error('Piper setup failed: $e');
    } finally {
      _installingPiper = false;
      await checkDeps();
      notifyListeners();
    }
  }

  /// Whether Kokoro is selected but its model/voices still need downloading.
  bool get needsKokoroSetup {
    final o = _options;
    return o != null &&
        o.backend == TtsBackendKind.kokoro &&
        (statusOf(DependencyKind.espeakNg)?.found ?? false) &&
        !kokoroInstaller.isInstalled();
  }

  bool _installingKokoro = false;

  /// Whether a Kokoro download is in progress.
  bool get installingKokoro => _installingKokoro;

  /// Downloads the Kokoro model + voices, streaming progress, then re-checks.
  Future<void> setupKokoro() async {
    if (_installingKokoro) return;
    _installingKokoro = true;
    notifyListeners();
    try {
      await for (final line in kokoroInstaller.ensureInstalled()) {
        log.info(line);
      }
    } on Object catch (e) {
      log.error('Kokoro setup failed: $e');
    } finally {
      _installingKokoro = false;
      await checkDeps();
      notifyListeners();
    }
  }

  /// Whether the Piper engine can be auto-installed on this platform.
  bool get piperAutoInstallSupported => piperInstaller.autoInstallSupported;

  /// A short reason an unavailable [backend] can't be selected, for the UI.
  String unavailableReason(TtsBackendKind backend) => switch (backend) {
        TtsBackendKind.piper =>
          piperAutoInstallSupported ? 'needs download' : 'no macOS build',
        TtsBackendKind.kokoro => (statusOf(DependencyKind.espeakNg)?.found ?? false)
            ? 'needs download'
            : 'needs espeak-ng',
        _ => 'unavailable',
      };

  /// Engine preference order: local engines first (free, offline), then cloud.
  static const List<TtsBackendKind> _backendPreference = [
    TtsBackendKind.piper,
    TtsBackendKind.kokoro,
    TtsBackendKind.openai,
    TtsBackendKind.elevenlabs,
  ];

  /// The best engine to pre-select: the first *available* one in preference
  /// order (local before cloud), falling back to OpenAI if none are ready.
  TtsBackendKind preferredBackend() {
    for (final k in _backendPreference) {
      if (backendAvailable(k)) return k;
    }
    return TtsBackendKind.openai;
  }

  /// Whether the *currently selected* engine can actually run: it is available
  /// and, for cloud engines, an API key is set.
  bool get selectedBackendReady {
    final o = _options;
    if (o == null) return false;
    if (!backendAvailable(o.backend)) return false;
    if (o.backend.isCloud) {
      return (o.apiKeys[o.backend.name] ?? '').trim().isNotEmpty;
    }
    return true;
  }

  /// Installs missing system packages, streaming log lines, then re-checks.
  Future<void> installMissing() async {
    if (_installing) return;
    _installing = true;
    notifyListeners();
    try {
      final installer = DependencyInstaller.forOs(os, runner);
      await for (final line in installer.install(missingDeps.map((d) => d.kind).toList())) {
        log.info(line);
      }
      await checkDeps();
    } finally {
      _installing = false;
      notifyListeners();
    }
  }

  /// Whether the Convert action should be enabled: a book is loaded, an output
  /// path is set, not already converting, and the backend is runnable (cloud →
  /// API key present; local → required deps found).
  bool get canConvert {
    final o = _options;
    if (o == null || _book == null || isConverting) return false;
    if (o.outputPath.trim().isEmpty) return false;
    if (o.selectedChapterIndices.isEmpty) return false;
    return _depsChecked && selectedBackendReady;
  }

  /// Starts the conversion using the selected backend.
  Future<void> startConversion() async {
    final o = _options;
    final b = _book;
    if (o == null || b == null) return;
    try {
      final backend = makeBackend(o,
          runner: runner,
          httpClient: httpClient,
          modelsDir: modelsDir,
          piper: piperInstaller,
          kokoro: kokoroInstaller);
      await conversion.run(b, o, backend: backend, ffmpeg: ffmpeg);
    } on Object catch (e) {
      log.error('Conversion could not start: $e');
      conversion.markError('Could not start: $e');
    }
  }

  /// Requests cancellation of an in-flight run.
  void cancel() => conversion.cancel();

  /// Filesystem-safe file stem from a book title.
  String _safeName(String title) {
    final cleaned = title.replaceAll(RegExp(r'[^\w\- ]+'), '').trim();
    return cleaned.isEmpty ? 'audiobook' : cleaned;
  }

  @override
  void dispose() {
    conversion.removeListener(notifyListeners);
    super.dispose();
  }
}

/// Detects the [HostOs] for the running platform.
HostOs currentHostOs() {
  if (Platform.isMacOS) return HostOs.macos;
  if (Platform.isWindows) return HostOs.windows;
  return HostOs.linux;
}
