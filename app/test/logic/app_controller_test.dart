import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:audiobook_studio/data/audio/ffmpeg_service.dart';
import 'package:audiobook_studio/data/deps/dependency_checker.dart';
import 'package:audiobook_studio/data/epub/epub_parser.dart';
import 'package:audiobook_studio/data/process_runner.dart';
import 'package:audiobook_studio/domain/conversion_options.dart';
import 'package:audiobook_studio/domain/dependency.dart';
import 'package:audiobook_studio/domain/progress.dart';
import 'package:audiobook_studio/logic/app_controller.dart';
import 'package:audiobook_studio/logic/conversion_controller.dart';
import 'package:audiobook_studio/logic/log_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

AppController controllerWith(Set<String> present) {
  final runner = ConfigurableRunner(present);
  final log = LogController();
  return AppController(
    parser: EpubParser(),
    ffmpeg: FfmpegService(runner),
    runner: runner,
    httpClient: MockClient((_) async => http.Response('', 200)),
    checker: DependencyChecker(runner),
    log: log,
    conversion: ConversionController(log: log),
    os: HostOs.macos,
    modelsDir: '/tmp/models',
    checkOnStart: false,
  );
}

void main() {
  test('cloud engines are always selectable; local need their tools', () async {
    final c = controllerWith({'ffmpeg', 'ffprobe'}); // no piper, no espeak
    await c.checkDeps();
    expect(c.backendAvailable(TtsBackendKind.openai), isTrue);
    expect(c.backendAvailable(TtsBackendKind.elevenlabs), isTrue);
    expect(c.backendAvailable(TtsBackendKind.piper), isFalse); // piper missing
    expect(c.backendAvailable(TtsBackendKind.kokoro), isFalse); // model missing
  });

  test('piper becomes available once the binary is present', () async {
    final c = controllerWith({'ffmpeg', 'ffprobe', 'piper'});
    await c.checkDeps();
    expect(c.backendAvailable(TtsBackendKind.piper), isTrue);
  });

  test('required-only gating: environmentReady ignores optional engine tools',
      () async {
    final c = controllerWith({'ffmpeg', 'ffprobe'});
    await c.checkDeps();
    expect(c.environmentReady, isTrue); // ffmpeg/ffprobe present is enough
    expect(c.missingRequired, isEmpty);
  });

  test('a failed start surfaces as an error in the progress view', () async {
    final c = controllerWith({'ffmpeg', 'ffprobe', 'espeak-ng'});
    await c.loadBook(_fixture(), '/books/t.epub');
    // Force the (unwired) Kokoro engine, which throws when constructed.
    c.updateOptions((o) => o.copyWith(backend: TtsBackendKind.kokoro));
    await c.startConversion();
    expect(c.progress.phase, ConvPhase.error);
    expect(c.progress.message, contains('Could not start'));
  });
}
