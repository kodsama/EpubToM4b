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
      final dir = p.dirname(sourcePath);
      final safe = _safeName(book.title);
      _options = ConversionOptions.defaults(
        book,
        outputPath: p.join(dir, '$safe.m4b'),
        workDir: p.join(dir, '$safe.work'),
        voiceId: VoiceCatalog.defaultVoiceId(
            TtsBackendKind.piper, book.languageCode),
      );
      log.info('Loaded "${book.title}" — ${book.chapters.length} chapters');
      notifyListeners();
      await checkDeps();
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

  /// Whether the toolkit is ready to proceed: every *required* dependency
  /// (ffmpeg/ffprobe) is present. Engine-specific tools are optional and don't
  /// block choosing a book — they only gate that specific engine.
  bool get environmentReady => _depsChecked && missingRequired.isEmpty;

  /// Whether [backend] is installed/configured enough to be *selectable*.
  ///
  /// Cloud engines are always selectable (you configure them by entering an API
  /// key after selecting). Local engines require their tools to be present:
  /// Piper needs the piper binary; Kokoro needs espeak-ng and its model. This
  /// excludes the API-key check, which gates conversion (not selection).
  bool backendAvailable(TtsBackendKind backend) {
    if (!_depsChecked) return backend.isCloud;
    if (backend.isCloud) return true;
    final binsOk = checker
        .requiredFor(backend)
        .where((k) => k.binaryName != null)
        .every((k) => statusOf(k)?.found ?? false);
    if (backend == TtsBackendKind.kokoro) {
      return binsOk && (statusOf(DependencyKind.kokoroModel)?.found ?? false);
    }
    return binsOk;
  }

  /// A short reason an unavailable [backend] can't be selected, for the UI.
  String unavailableReason(TtsBackendKind backend) => switch (backend) {
        TtsBackendKind.piper => 'install piper',
        TtsBackendKind.kokoro => 'needs Kokoro model',
        _ => 'unavailable',
      };

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
          runner: runner, httpClient: httpClient, modelsDir: modelsDir);
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
