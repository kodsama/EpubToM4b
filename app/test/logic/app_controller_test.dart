import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:audiobook_studio/data/audio/ffmpeg_service.dart';
import 'package:audiobook_studio/data/deps/dependency_checker.dart';
import 'package:audiobook_studio/data/deps/kokoro_installer.dart';
import 'package:audiobook_studio/data/deps/piper_installer.dart';
import 'package:audiobook_studio/data/epub/epub_parser.dart';
import 'package:audiobook_studio/data/process_runner.dart';
import 'package:audiobook_studio/domain/conversion_options.dart';
import 'package:audiobook_studio/domain/dependency.dart';
import 'package:audiobook_studio/logic/app_controller.dart';
import 'package:audiobook_studio/logic/conversion_controller.dart';
import 'package:audiobook_studio/logic/log_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

/// Reports only the named binaries as present on PATH.
class ConfigurableRunner extends ProcessRunner {
  final Set<String> present;
  ConfigurableRunner(this.present);

  @override
  Future<ProcessRunResult> run(String e, List<String> a, {String? stdinText}) async {
    if (e == 'which' || e == 'where') {
      final bin = a.first;
      return present.contains(bin)
          ? ProcessRunResult(0, '/usr/bin/$bin\n', '')
          : const ProcessRunResult(1, '', '');
    }
    return ProcessRunResult(0, '$e version 1.0', '');
  }

  @override
  Stream<String> stream(String e, List<String> a, {String? stdinText}) =>
      const Stream.empty();
}

Uint8List _fixture() {
  final a = Archive();
  void add(String n, String c) => a.addFile(ArchiveFile(n, c.length, utf8.encode(c)));
  add('META-INF/container.xml',
      '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="c.opf"/></rootfiles></container>');
  add('c.opf',
      '<package xmlns="http://www.idpf.org/2007/opf"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>T</dc:title><dc:language>fr</dc:language></metadata><manifest><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="a"/></spine></package>');
  add('a.xhtml', '<html><body><h1>One</h1><p>Some readable text content here.</p></body></html>');
  return Uint8List.fromList(ZipEncoder().encode(a));
}

late Directory _tmp;

/// Creates fake Piper binary + voice files so the installer reports installed.
void installPiperFiles(PiperInstaller piper, String voiceId) {
  Directory(piper.piperDir).createSync(recursive: true);
  File(piper.binaryPath).writeAsBytesSync(const [0]);
  File(piper.voicePath(voiceId)).writeAsBytesSync(const [0]);
  File(piper.voiceConfigPath(voiceId)).writeAsStringSync('{}');
}

({AppController controller, PiperInstaller piper, KokoroInstaller kokoro})
    build(Set<String> present) {
  final runner = ConfigurableRunner(present);
  final log = LogController();
  final client = MockClient((_) async => http.Response('', 200));
  final mdir = p.join(_tmp.path, 'm${present.hashCode}${present.length}');
  final piper = PiperInstaller(modelsDir: mdir, client: client);
  final kokoro = KokoroInstaller(modelsDir: mdir, client: client);
  final controller = AppController(
    parser: EpubParser(),
    ffmpeg: FfmpegService(runner),
    runner: runner,
    httpClient: client,
    checker: DependencyChecker(runner, piper: piper, kokoro: kokoro),
    piperInstaller: piper,
    kokoroInstaller: kokoro,
    log: log,
    conversion: ConversionController(log: log),
    os: HostOs.macos,
    modelsDir: piper.modelsDir,
    checkOnStart: false,
  );
  return (controller: controller, piper: piper, kokoro: kokoro);
}

/// Creates fake Kokoro model + voices files so the installer reports installed.
void installKokoroFiles(KokoroInstaller k) {
  Directory(k.kokoroDir).createSync(recursive: true);
  File(k.modelPath).writeAsBytesSync(const [0]);
  File(k.voicesPath).writeAsBytesSync(const [0]);
}

void main() {
  setUp(() => _tmp = Directory.systemTemp.createTempSync('appctrl_'));
  tearDown(() => _tmp.deleteSync(recursive: true));

  test('cloud engines are always selectable; local need their tools', () async {
    final c = build({'ffmpeg', 'ffprobe'}).controller;
    await c.checkDeps();
    expect(c.backendAvailable(TtsBackendKind.openai), isTrue);
    expect(c.backendAvailable(TtsBackendKind.elevenlabs), isTrue);
    expect(c.backendAvailable(TtsBackendKind.piper), isFalse); // not downloaded
    expect(c.backendAvailable(TtsBackendKind.kokoro), isFalse);
  });

  test('piper becomes available once binary + voice are downloaded', () async {
    final b = build({'ffmpeg', 'ffprobe'});
    installPiperFiles(b.piper, 'fr_FR-siwis-medium'); // default fr voice
    await b.controller.loadBook(_fixture(), '/books/t.epub');
    expect(b.controller.backendAvailable(TtsBackendKind.piper), isTrue);
    expect(b.controller.options!.backend, TtsBackendKind.piper); // preferred
  });

  test('core tools ready with ffmpeg/ffprobe, but not "Ready" with no engine',
      () async {
    final c = build({'ffmpeg', 'ffprobe'}).controller; // no engine installed
    await c.checkDeps();
    expect(c.coreToolsReady, isTrue);
    expect(c.missingRequired, isEmpty);
    // No local engine installed and no cloud key → not overall-ready.
    expect(c.anyEngineReady, isFalse);
    expect(c.environmentReady, isFalse);
  });

  test('anyEngineReady becomes true once a cloud key is entered', () async {
    final c = build({'ffmpeg', 'ffprobe'}).controller;
    await c.loadBook(_fixture(), '/books/t.epub'); // defaults to a cloud engine
    expect(c.anyEngineReady, isFalse);
    c.updateOptions((o) =>
        o.copyWith(apiKeys: {o.backend.name: 'sk-test'}));
    expect(c.anyEngineReady, isTrue);
    expect(c.environmentReady, isTrue);
  });

  test('preferredBackend favours local Piper when it is installed', () async {
    final b = build({'ffmpeg', 'ffprobe'});
    installPiperFiles(b.piper, 'fr_FR-siwis-medium');
    // Load so the book language (fr) drives the default voice check.
    await b.controller.loadBook(_fixture(), '/books/t.epub');
    expect(b.controller.preferredBackend(), TtsBackendKind.piper);
  });

  test('preferredBackend falls back to cloud when no local engine is ready',
      () async {
    final c = build({'ffmpeg', 'ffprobe'}).controller;
    await c.checkDeps();
    expect(c.preferredBackend(), TtsBackendKind.openai);
  });

  test('loadBook pre-selects a usable engine, not an unavailable one', () async {
    final c = build({'ffmpeg', 'ffprobe'}).controller; // piper not downloaded
    await c.loadBook(_fixture(), '/books/t.epub');
    expect(c.options!.backend, TtsBackendKind.openai);
    expect(c.backendAvailable(c.options!.backend), isTrue);
  });

  test('needsPiperSetup is true when Piper is chosen but not downloaded',
      () async {
    final c = build({'ffmpeg', 'ffprobe'}).controller;
    await c.loadBook(_fixture(), '/books/t.epub');
    c.updateOptions((o) => o.copyWith(backend: TtsBackendKind.piper));
    expect(c.needsPiperSetup, isTrue);
  });

  test('kokoro needs espeak-ng + a model download before it is available',
      () async {
    final b = build({'ffmpeg', 'ffprobe', 'espeak-ng'});
    await b.controller.loadBook(_fixture(), '/books/t.epub');
    // espeak present but model not downloaded yet → unavailable, setup needed.
    expect(b.controller.backendAvailable(TtsBackendKind.kokoro), isFalse);
    b.controller.updateOptions((o) => o.copyWith(backend: TtsBackendKind.kokoro));
    expect(b.controller.needsKokoroSetup, isTrue);

    // After the model + voices are present, Kokoro is available.
    installKokoroFiles(b.kokoro);
    await b.controller.checkDeps();
    expect(b.controller.backendAvailable(TtsBackendKind.kokoro), isTrue);
    expect(b.controller.needsKokoroSetup, isFalse);
  });

  test('kokoro is unavailable without espeak-ng even if the model exists',
      () async {
    final b = build({'ffmpeg', 'ffprobe'}); // no espeak-ng
    installKokoroFiles(b.kokoro);
    await b.controller.loadBook(_fixture(), '/books/t.epub');
    expect(b.controller.backendAvailable(TtsBackendKind.kokoro), isFalse);
  });
}
