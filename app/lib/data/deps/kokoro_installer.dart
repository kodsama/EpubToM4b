/// Downloads and locates the Kokoro ONNX model and voice pack.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Release the model artifacts are pinned to.
const String kKokoroRelease = 'model-files-v1.0';

/// Manages the on-disk Kokoro model (`kokoro.onnx`) and voices (`voices.bin`).
class KokoroInstaller {
  /// Root models directory.
  final String modelsDir;

  /// HTTP client for downloads.
  final http.Client client;

  KokoroInstaller({required this.modelsDir, required this.client});

  /// Directory holding the Kokoro files.
  String get kokoroDir => p.join(modelsDir, 'kokoro');

  /// Absolute path of the ONNX model (int8, ~88 MB).
  String get modelPath => p.join(kokoroDir, 'kokoro-v1.0.int8.onnx');

  /// Absolute path of the voices pack (~27 MB).
  String get voicesPath => p.join(kokoroDir, 'voices-v1.0.bin');

  /// Whether both model and voices are present.
  bool isInstalled() =>
      File(modelPath).existsSync() && File(voicesPath).existsSync();

  /// Base release download URL.
  static String _asset(String name) =>
      'https://github.com/thewh1teagle/kokoro-onnx/releases/download/$kKokoroRelease/$name';

  /// Model download URL (int8).
  static String get modelUrl => _asset('kokoro-v1.0.int8.onnx');

  /// Voices download URL.
  static String get voicesUrl => _asset('voices-v1.0.bin');

  /// Downloads whatever is missing, streaming progress lines.
  Stream<String> ensureInstalled() async* {
    Directory(kokoroDir).createSync(recursive: true);
    if (!File(modelPath).existsSync()) {
      yield 'Downloading Kokoro model (~88 MB)…';
      File(modelPath).writeAsBytesSync(await _download(modelUrl));
      yield 'Kokoro model installed.';
    } else {
      yield 'Kokoro model already installed.';
    }
    if (!File(voicesPath).existsSync()) {
      yield 'Downloading Kokoro voices (~27 MB)…';
      File(voicesPath).writeAsBytesSync(await _download(voicesUrl));
      yield 'Kokoro voices installed.';
    } else {
      yield 'Kokoro voices already installed.';
    }
    yield 'Kokoro is ready.';
  }

  Future<Uint8List> _download(String url) async {
    final resp = await client.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw HttpException('Download failed (${resp.statusCode}): $url');
    }
    return resp.bodyBytes;
  }
}
