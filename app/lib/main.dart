/// Audiobook Studio — app entry point. Wires the dependency graph and launches
/// the single-window desktop UI.
library;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/audio/ffmpeg_kit_executor.dart';
import 'data/audio/ffmpeg_service.dart';
import 'data/deps/dependency_checker.dart';
import 'data/deps/sherpa_model_installer.dart';
import 'data/epub/epub_parser.dart';
import 'data/process_runner.dart';
import 'logic/app_controller.dart';
import 'logic/conversion_controller.dart';
import 'logic/log_controller.dart';
import 'logic/theme_controller.dart';
import 'ui/home_screen.dart';
import 'ui/licenses.dart';
import 'ui/theme.dart';
import 'util/platform_env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerProjectLicenses();
  final support = await getApplicationSupportDirectory();
  final theme = await ThemeController.load(support.path);
  // On mobile, output goes to app-scoped storage and scratch to the temp dir.
  final outputDir =
      isMobilePlatform ? (await getApplicationDocumentsDirectory()).path : null;
  final workBaseDir =
      isMobilePlatform ? (await getTemporaryDirectory()).path : null;
  final controller = buildAppController(
    modelsDir: p.join(support.path, 'models'),
    mobile: isMobilePlatform,
    outputDir: outputDir,
    workBaseDir: workBaseDir,
  );
  runApp(AudiobookStudioApp(controller: controller, theme: theme));
}

/// Constructs an [AppController] with production collaborators. Exposed so the
/// few wiring choices live in one place (and can be overridden in tests). On
/// [mobile], ffmpeg runs in-process (ffmpeg-kit) and dependency probing is
/// skipped since the binaries are bundled.
AppController buildAppController({
  required String modelsDir,
  bool mobile = false,
  String? outputDir,
  String? workBaseDir,
}) {
  final runner = SystemProcessRunner();
  final log = LogController();
  final httpClient = http.Client();
  final sherpa = SherpaModelInstaller(modelsDir: modelsDir, client: httpClient);
  return AppController(
    parser: EpubParser(),
    ffmpeg: mobile
        ? FfmpegService(runner, executor: FfmpegKitExecutor())
        : FfmpegService(runner),
    runner: runner,
    httpClient: httpClient,
    checker: DependencyChecker(runner, bundled: mobile),
    sherpaInstaller: sherpa,
    log: log,
    conversion: ConversionController(log: log),
    os: currentHostOs(),
    outputDir: outputDir,
    workBaseDir: workBaseDir,
  );
}

/// The root widget. Rebuilds the [MaterialApp] when the [theme] choice changes,
/// applying the matching palette ([AppTokens.brightness] drives the custom
/// widget colors, so it must be set before the tree builds).
class AudiobookStudioApp extends StatelessWidget {
  final AppController controller;
  final ThemeController theme;
  const AudiobookStudioApp(
      {super.key, required this.controller, required this.theme});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: theme,
      builder: (context, mode, _) {
        final brightness =
            mode == ThemeMode.light ? Brightness.light : Brightness.dark;
        return MaterialApp(
          title: 'Audiobook Studio',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(brightness),
          home: HomeScreen(controller: controller, theme: theme),
        );
      },
    );
  }
}
