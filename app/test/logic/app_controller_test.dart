import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:audiobook_studio/data/audio/ffmpeg_service.dart';
import 'package:audiobook_studio/data/deps/dependency_checker.dart';
import 'package:audiobook_studio/data/deps/sherpa_model_installer.dart';
import 'package:audiobook_studio/data/epub/epub_parser.dart';
import 'package:audiobook_studio/data/process_runner.dart';
import 'package:audiobook_studio/data/tts/sherpa_catalog.dart';
import 'package:audiobook_studio/domain/conversion_options.dart';
import 'package:audiobook_studio/domain/dependency.dart';
import 'package:audiobook_studio/logic/app_controller.dart';
import 'package:audiobook_studio/logic/conversion_controller.dart';
import 'package:audiobook_studio/logic/log_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

/// Reports ffmpeg/ffprobe present (or absent) for deterministic gating.
class ConfigurableRunner extends ProcessRunner {
  final bool toolsPresent;
  ConfigurableRunner({this.toolsPresent = true});

  @override
  Future<ProcessRunResult> run(String e, List<String> a, {String? stdinText}) async {
    if (e == 'which' || e == 'where') {
      return toolsPresent
          ? ProcessRunResult(0, '/usr/bin/${a.first}\n', '')
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

/// Creates fake files for every voice of [model] so it reports installed.
void installModelFiles(SherpaModelInstaller inst, SherpaModel model) {
  for (final v in model.voices) {
    final f = File(inst.modelPath(v));
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(const [0]);
    if (v.vocoderFile.isNotEmpty) {
      File(inst.vocoderPath(v)).writeAsBytesSync(const [0]);
    }
  }
}

({AppController controller, SherpaModelInstaller sherpa}) build(
    {bool toolsPresent = true}) {
  final runner = ConfigurableRunner(toolsPresent: toolsPresent);
  final log = LogController();
  final client = MockClient((_) async => http.Response('', 200));
  final sherpa = SherpaModelInstaller(
      modelsDir: p.join(_tmp.path, 'm$toolsPresent'), client: client);
  final controller = AppController(
    parser: EpubParser(),
    ffmpeg: FfmpegService(runner),
    runner: runner,
    httpClient: client,
    checker: DependencyChecker(runner),
    sherpaInstaller: sherpa,
    log: log,
    conversion: ConversionController(log: log),
    os: HostOs.macos,
    checkOnStart: false,
  );
  return (controller: controller, sherpa: sherpa);
}

void main() {
  setUp(() => _tmp = Directory.systemTemp.createTempSync('appctrl_'));
  tearDown(() => _tmp.deleteSync(recursive: true));

  test('cloud engines are always selectable; local needs a downloaded model',
      () async {
    final b = build();
    await b.controller.loadBook(_fixture(), '/books/t.epub');
    expect(b.controller.backendAvailable(TtsBackendKind.openai), isTrue);
    expect(b.controller.backendAvailable(TtsBackendKind.elevenlabs), isTrue);
    expect(b.controller.backendAvailable(TtsBackendKind.local), isFalse);
  });

  test('local engine available once its model is downloaded', () async {
    final b = build();
    await b.controller.loadBook(_fixture(), '/books/t.epub');
    final model = sherpaModelById(b.controller.options!.voiceId)!;
    installModelFiles(b.sherpa, model);
    await b.controller.checkDeps();
    expect(b.controller.backendAvailable(TtsBackendKind.local), isTrue);
    expect(b.controller.needsModelDownload, isFalse);
  });

  test('core tools present but no engine -> not Ready', () async {
    final b = build();
    await b.controller.checkDeps();
    expect(b.controller.coreToolsReady, isTrue);
    expect(b.controller.anyEngineReady, isFalse);
    expect(b.controller.environmentReady, isFalse);
  });

  test('loadBook pre-selects the local engine and a French model', () async {
    final b = build();
    await b.controller.loadBook(_fixture(), '/books/t.epub');
    expect(b.controller.options!.backend, TtsBackendKind.local);
    // French book -> a French model id is selected.
    expect(sherpaModelById(b.controller.options!.voiceId)!.languages,
        contains('fr'));
    expect(b.controller.needsModelDownload, isTrue);
  });

  test('cloud engine becomes ready once an API key is entered', () async {
    final b = build();
    await b.controller.loadBook(_fixture(), '/books/t.epub');
    await b.controller.setBackend(TtsBackendKind.openai);
    expect(b.controller.anyEngineReady, isFalse);
    b.controller.updateOptions(
        (o) => o.copyWith(apiKeys: {o.backend.name: 'sk-test'}));
    expect(b.controller.anyEngineReady, isTrue);
    expect(b.controller.canConvert, isTrue);
  });

  test('Convert disabled when ffmpeg/ffprobe are missing', () async {
    final b = build(toolsPresent: false);
    await b.controller.loadBook(_fixture(), '/books/t.epub');
    expect(b.controller.coreToolsReady, isFalse);
    expect(b.controller.canConvert, isFalse);
  });
}
