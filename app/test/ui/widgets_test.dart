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
import 'package:audiobook_studio/domain/progress.dart';
import 'package:audiobook_studio/logic/app_controller.dart';
import 'package:audiobook_studio/logic/conversion_controller.dart';
import 'package:audiobook_studio/logic/log_controller.dart';
import 'package:audiobook_studio/ui/theme.dart';
import 'package:audiobook_studio/ui/widgets/convert_bar.dart';
import 'package:audiobook_studio/ui/widgets/options_panel.dart';
import 'package:audiobook_studio/ui/widgets/progress_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Reports binaries as present (or absent) so dependency gating is deterministic.
class FakeRunner extends ProcessRunner {
  final bool found;
  FakeRunner({this.found = true});

  @override
  Future<ProcessRunResult> run(String e, List<String> a, {String? stdinText}) async {
    if (e == 'which' || e == 'where') {
      return found
          ? const ProcessRunResult(0, '/usr/bin/tool\n', '')
          : const ProcessRunResult(1, '', 'not found');
    }
    return const ProcessRunResult(0, 'tool version 1.0', ''); // -version
  }

  @override
  Stream<String> stream(String e, List<String> a, {String? stdinText}) =>
      const Stream.empty();
}

/// Minimal EPUB (no cover, two chapters) for loading into the controller.
Uint8List fixtureEpub() {
  final a = Archive();
  void add(String n, String c) => a.addFile(ArchiveFile(n, c.length, utf8.encode(c)));
  add('META-INF/container.xml',
      '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="c.opf"/></rootfiles></container>');
  add('c.opf', '''
<package xmlns="http://www.idpf.org/2007/opf">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:title>Test Book</dc:title><dc:creator>Author X</dc:creator><dc:language>en</dc:language></metadata>
<manifest><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>
<item id="b" href="b.xhtml" media-type="application/xhtml+xml"/></manifest>
<spine><itemref idref="a"/><itemref idref="b"/></spine></package>''');
  add('a.xhtml', '<html><body><h1>Chapter A</h1><p>Some readable content here for chapter A.</p></body></html>');
  add('b.xhtml', '<html><body><h1>Chapter B</h1><p>Some readable content here for chapter B.</p></body></html>');
  return Uint8List.fromList(ZipEncoder().encode(a));
}

AppController makeController({bool depsFound = true}) {
  final runner = FakeRunner(found: depsFound);
  final log = LogController();
  final client = MockClient((_) async => http.Response('', 200));
  final mdir = Directory.systemTemp.createTempSync('wtest_').path;
  final piper = PiperInstaller(modelsDir: mdir, client: client);
  final kokoro = KokoroInstaller(modelsDir: mdir, client: client);
  return AppController(
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
  );
}

Widget wrap(Widget child) =>
    MaterialApp(theme: buildAppTheme(), home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('ConvertBar is disabled before a book is loaded', (tester) async {
    final c = makeController();
    await tester.pumpWidget(wrap(ConvertBar(controller: c)));
    final btn = tester.widget<FilledButton>(
        find.byKey(const Key('convert-button')));
    expect(btn.onPressed, isNull); // disabled
  });

  testWidgets('ConvertBar enables once a book is loaded and an engine is ready',
      (tester) async {
    final c = makeController(depsFound: true);
    await c.loadBook(fixtureEpub(), '/books/test.epub');
    // Default engine is cloud (no local Piper downloaded); provide its key.
    c.updateOptions((o) => o.copyWith(apiKeys: {o.backend.name: 'sk-test'}));
    await tester.pumpWidget(wrap(ConvertBar(controller: c)));
    await tester.pump();
    expect(c.book, isNotNull);
    expect(c.canConvert, isTrue);
    final btn = tester.widget<FilledButton>(
        find.byKey(const Key('convert-button')));
    expect(btn.onPressed, isNotNull); // enabled
  });

  testWidgets('ConvertBar stays disabled when dependencies are missing',
      (tester) async {
    final c = makeController(depsFound: false);
    await c.loadBook(fixtureEpub(), '/books/test.epub');
    await tester.pumpWidget(wrap(ConvertBar(controller: c)));
    await tester.pump();
    expect(c.canConvert, isFalse);
  });

  testWidgets('OptionsPanel shows the API-key field only for cloud backends',
      (tester) async {
    final c = makeController();
    await c.loadBook(fixtureEpub(), '/books/test.epub');
    // Mirror the home screen: rebuild the panel when the controller changes.
    await tester.pumpWidget(wrap(ListenableBuilder(
      listenable: c,
      builder: (context, _) => OptionsPanel(controller: c),
    )));
    await tester.pumpAndSettle();

    // Force a local engine → no API key field.
    c.updateOptions((o) => o.copyWith(backend: TtsBackendKind.piper));
    await tester.pumpAndSettle();
    expect(find.textContaining('API key'), findsNothing);

    // Switch to a cloud engine → API key field appears.
    c.updateOptions((o) => o.copyWith(backend: TtsBackendKind.openai));
    await tester.pumpAndSettle();
    expect(find.textContaining('API key'), findsOneWidget);
  });

  testWidgets('ProgressView renders the global percentage and chapter rows',
      (tester) async {
    const progress = ConversionProgress(
      phase: ConvPhase.synthesizing,
      chapters: [
        ChapterProgress(index: 0, title: 'Chapter A', totalChars: 100, doneChars: 50, status: ChapterStatus.synthesizing),
        ChapterProgress(index: 1, title: 'Chapter B', totalChars: 100, doneChars: 0),
      ],
    );
    await tester.pumpWidget(wrap(const ProgressView(progress: progress)));
    await tester.pump();
    expect(find.text('25%'), findsOneWidget); // 50/200
    expect(find.text('Chapter A'), findsOneWidget);
    expect(find.text('Chapter B'), findsOneWidget);
    expect(find.text('Narrating'), findsOneWidget);
  });
}
