/// Audiobook Studio — app entry point. Wires the dependency graph and launches
/// the single-window desktop UI.
library;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/audio/ffmpeg_service.dart';
import 'data/deps/dependency_checker.dart';
import 'data/deps/kokoro_installer.dart';
import 'data/deps/piper_installer.dart';
import 'data/epub/epub_parser.dart';
import 'data/process_runner.dart';
import 'logic/app_controller.dart';
import 'logic/conversion_controller.dart';
import 'logic/log_controller.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  final controller = buildAppController(modelsDir: p.join(support.path, 'models'));
  runApp(AudiobookStudioApp(controller: controller));
}

/// Constructs an [AppController] with production collaborators. Exposed so the
/// few wiring choices live in one place (and can be overridden in tests).
AppController buildAppController({required String modelsDir}) {
  final runner = SystemProcessRunner();
  final log = LogController();
  final httpClient = http.Client();
  final piper = PiperInstaller(modelsDir: modelsDir, client: httpClient);
  final kokoro = KokoroInstaller(modelsDir: modelsDir, client: httpClient);
  return AppController(
    parser: EpubParser(),
    ffmpeg: FfmpegService(runner),
    runner: runner,
    httpClient: httpClient,
    checker: DependencyChecker(runner, piper: piper, kokoro: kokoro),
    piperInstaller: piper,
    kokoroInstaller: kokoro,
    log: log,
    conversion: ConversionController(log: log),
    os: currentHostOs(),
    modelsDir: modelsDir,
  );
}

/// The root widget.
class AudiobookStudioApp extends StatelessWidget {
  final AppController controller;
  const AudiobookStudioApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audiobook Studio',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: HomeScreen(controller: controller),
    );
  }
}
