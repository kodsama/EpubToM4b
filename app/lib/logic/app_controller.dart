/// The UI-facing application state machine.
///
/// Ties together parsing, options, dependency checks, model downloads and the
/// conversion run behind one [ChangeNotifier] the widgets observe. Free of any
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
import '../data/deps/sherpa_model_installer.dart';
import '../data/epub/epub_parser.dart';
import '../data/process_runner.dart';
import '../data/tts/backend_factory.dart';
import '../data/tts/sherpa_catalog.dart';
import '../data/tts/voice_catalog.dart';
import '../domain/book.dart';
import '../domain/conversion_options.dart';
import '../domain/dependency.dart';
import '../domain/progress.dart';
import '../util/filename.dart';
import 'conversion_controller.dart';
import 'log_controller.dart';

/// Orchestrates the end-to-end UI workflow and exposes observable state.
class AppController extends ChangeNotifier {
  final EpubParser parser;
  final FfmpegService ffmpeg;
  final ProcessRunner runner;
  final http.Client httpClient;
  final DependencyChecker checker;
  final SherpaModelInstaller sherpaInstaller;
  final LogController log;
  final ConversionController conversion;
  final HostOs os;

  /// Base directory for the output `.m4b`. When null (desktop), output defaults
  /// next to the source file; on mobile the app passes its documents directory
  /// because writing beside the picked file is not permitted.
  final String? outputDir;

  /// Base directory for scratch files. When null (desktop), work happens next to
  /// the source file; on mobile the app passes a temporary directory.
  final String? workBaseDir;

  AppController({
    required this.parser,
    required this.ffmpeg,
    required this.runner,
    required this.httpClient,
    required this.checker,
    required this.sherpaInstaller,
    required this.log,
    required this.conversion,
    required this.os,
    this.outputDir,
    this.workBaseDir,
    bool checkOnStart = true,
  }) {
    conversion.addListener(notifyListeners);
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

  /// Latest dependency statuses.
  List<DependencyStatus> get deps => _deps;

  /// Whether a dependency check has completed at least once.
  bool get depsChecked => _depsChecked;

  /// Whether a system-package install is currently streaming.
  bool get installing => _installing;

  /// Whether a local model download is in progress.
  bool get installingModel => _downloadingModelId != null;

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

  /// The default voice/model id for an engine + language.
  String _defaultVoice(TtsBackendKind backend, String lang) => backend.isCloud
      ? VoiceCatalog.defaultVoiceId(backend, lang)
      : defaultSherpaModelId(lang);

  /// The selected local model descriptor, if the local engine is active.
  SherpaModel? get selectedModel {
    final o = _options;
    if (o == null || o.backend != TtsBackendKind.local) return null;
    return sherpaModelById(o.voiceId);
  }

  /// Whether at least one offline (local) voice supports the book's language.
  bool get hasLocalVoiceForLanguage {
    final b = _book;
    return b != null && sherpaModelsFor(b.languageCode).isNotEmpty;
  }

  /// A warning when the detected book language has no bundled offline voice —
  /// the user must use a cloud engine (which covers many languages) instead.
  /// Null when a local voice exists or no book is loaded.
  String? get languageSupportWarning {
    final b = _book;
    if (b == null || hasLocalVoiceForLanguage) return null;
    return 'No offline voice supports "${b.languageCode}". Pick a cloud engine '
        '(OpenAI or ElevenLabs) and add its API key, or choose a language an '
        'offline voice covers.';
  }

  /// Parses [bytes] from [sourcePath], derives default options, and checks deps.
  Future<void> loadBook(Uint8List bytes, String sourcePath) async {
    _parseError = null;
    try {
      final stem = p.basenameWithoutExtension(sourcePath);
      final book = parser.parse(bytes, fallbackTitle: stem);
      _book = book;
      await checkDeps();
      final backend = preferredBackend();
      final safe = _safeName(book.title);
      final outBase = outputDir ?? p.dirname(sourcePath);
      final workBase = workBaseDir ?? p.dirname(sourcePath);
      _options = ConversionOptions.defaults(
        book,
        outputPath: p.join(outBase, '$safe.m4b'),
        workDir: p.join(workBase, '$safe.work'),
        voiceId: _defaultVoice(backend, book.languageCode),
      ).copyWith(backend: backend);
      log.info('Loaded "${book.title}" — ${book.chapters.length} chapters '
          '· engine: ${backend.label}');
      final warning = languageSupportWarning;
      if (warning != null) log.warn(warning);
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

  /// Switches engine and resets language/voice to that engine's defaults.
  Future<void> setBackend(TtsBackendKind backend) async {
    final o = _options;
    final b = _book;
    if (o == null || b == null) return;
    _options = o.copyWith(
      backend: backend,
      languageCode: b.languageCode,
      voiceId: _defaultVoice(backend, b.languageCode),
    );
    notifyListeners();
  }

  /// Sets the narration language and resets the voice/model to its default.
  void setLanguage(String code) {
    final o = _options;
    if (o == null) return;
    _options = o.copyWith(
      languageCode: code,
      voiceId: _defaultVoice(o.backend, code),
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

  /// Probes the system tools (ffmpeg/ffprobe). Runs on launch.
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

  /// Whether the core tools (ffmpeg/ffprobe) are present. Gates choosing a book.
  bool get coreToolsReady => _depsChecked && missingRequired.isEmpty;

  /// Whether at least one TTS engine is usable now: a local model is downloaded,
  /// or a cloud engine has an API key entered.
  bool get anyEngineReady => TtsBackendKind.values.any((k) {
        if (!backendAvailable(k)) return false;
        if (k.isCloud) {
          return (_options?.apiKeys[k.name] ?? '').trim().isNotEmpty;
        }
        return true;
      });

  /// Overall readiness shown as "Ready".
  bool get environmentReady => coreToolsReady && anyEngineReady;

  /// Whether [backend] is usable enough to run. Cloud is always "available"
  /// (configured via API key); local requires the selected model downloaded.
  bool backendAvailable(TtsBackendKind backend) {
    if (backend.isCloud) return true;
    if (!_depsChecked) return false;
    final model = _localModelFor(backend);
    return model != null && sherpaInstaller.isInstalled(model);
  }

  /// Resolves the local model that [backend] would use (selected, else default).
  SherpaModel? _localModelFor(TtsBackendKind backend) {
    if (backend != TtsBackendKind.local) return null;
    final id = _options?.voiceId ??
        defaultSherpaModelId(_book?.languageCode ?? 'en');
    return sherpaModelById(id);
  }

  /// Whether the local engine is selected but its model still needs downloading.
  bool get needsModelDownload {
    final o = _options;
    return o != null &&
        o.backend == TtsBackendKind.local &&
        !backendAvailable(TtsBackendKind.local);
  }

  /// Whether [model]'s files are present on disk.
  bool isModelInstalled(SherpaModel model) => sherpaInstaller.isInstalled(model);

  String? _downloadingModelId;
  double _downloadProgress = 0;

  /// The id of the model currently downloading, or null.
  String? get downloadingModelId => _downloadingModelId;

  /// Download completion (0–1) of the model currently downloading.
  double get downloadProgress => _downloadProgress;

  /// Downloads the selected local model (used by the options-panel button).
  Future<void> setupModel() async {
    final model = _localModelFor(TtsBackendKind.local);
    if (model != null) await downloadModel(model);
  }

  /// Downloads a specific [model] (+ vocoder), streaming progress, then selects
  /// it as the active local voice so it's ready to use.
  Future<void> downloadModel(SherpaModel model) async {
    if (_downloadingModelId != null) return;
    _downloadingModelId = model.id;
    _downloadProgress = 0;
    notifyListeners();
    try {
      final stream = sherpaInstaller.ensureInstalled(model, onProgress: (f) {
        // Throttle to ~1% steps to avoid excessive rebuilds.
        if (f - _downloadProgress >= 0.01 || f >= 1.0) {
          _downloadProgress = f;
          notifyListeners();
        }
      });
      await for (final line in stream) {
        log.info(line);
      }
      final o = _options;
      if (o != null && o.backend == TtsBackendKind.local) {
        _options = o.copyWith(voiceId: model.id);
      }
    } on Object catch (e) {
      log.error('Model download failed: $e');
    } finally {
      _downloadingModelId = null;
      _downloadProgress = 0;
      await checkDeps();
      notifyListeners();
    }
  }

  /// Installed local models (their voices are downloaded), for the manage UI.
  List<SherpaModel> get installedModels =>
      kSherpaModels.where(sherpaInstaller.isInstalled).toList();

  /// Deletes a downloaded [model] from disk and refreshes availability.
  Future<void> uninstallModel(SherpaModel model) async {
    sherpaInstaller.uninstall(model);
    log.info('Removed ${model.label}');
    await checkDeps();
    notifyListeners();
  }

  /// A short reason an unavailable [backend] can't run, for the UI.
  String unavailableReason(TtsBackendKind backend) =>
      backend == TtsBackendKind.local ? 'download a model' : 'unavailable';

  /// The engine to pre-select. Always the free, offline local engine — if its
  /// model isn't downloaded yet, the UI offers a one-click download. Users can
  /// switch to a cloud engine explicitly.
  TtsBackendKind preferredBackend() => TtsBackendKind.local;

  /// Whether the selected engine can run now: available and (cloud) keyed.
  bool get selectedBackendReady {
    final o = _options;
    if (o == null) return false;
    if (!backendAvailable(o.backend)) return false;
    if (o.backend.isCloud) {
      return (o.apiKeys[o.backend.name] ?? '').trim().isNotEmpty;
    }
    return true;
  }

  /// Installs missing system packages (ffmpeg), streaming log lines.
  Future<void> installMissing() async {
    if (_installing) return;
    _installing = true;
    notifyListeners();
    try {
      final installer = DependencyInstaller.forOs(os, runner);
      await for (final line
          in installer.install(missingDeps.map((d) => d.kind).toList())) {
        log.info(line);
      }
      await checkDeps();
    } finally {
      _installing = false;
      notifyListeners();
    }
  }

  /// Whether the Convert action should be enabled.
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
    final backend = makeBackend(o,
        runner: runner, httpClient: httpClient, sherpa: sherpaInstaller);
    try {
      await conversion.run(b, o, backend: backend, ffmpeg: ffmpeg);
    } on Object catch (e) {
      log.error('Conversion could not start: $e');
      conversion.markError('Could not start: $e');
    } finally {
      await backend.dispose();
    }
  }

  /// The step the walkthrough should focus on (1-based):
  /// 1 toolkit · 2 choose book · 3 tune · 4 convert · 5 progress.
  int get currentStep {
    if (!coreToolsReady) return 1;
    if (_book == null) return 2;
    if (isConverting ||
        progress.phase == ConvPhase.done ||
        progress.phase == ConvPhase.error) {
      return 5;
    }
    if (canConvert) return 4;
    return 3;
  }

  /// Requests cancellation of an in-flight run.
  void cancel() => conversion.cancel();

  /// Filesystem-safe file stem from a book title. Keeps accents, apostrophes and
  /// other normal characters — only strips characters illegal in file names
  /// (the old `[^\w\- ]` form deleted é/è/à and apostrophes, e.g. turning
  /// "L'élégance" into "Llgance").
  String _safeName(String title) => safeFileStem(title);

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
