/// Downloads and extracts sherpa-onnx TTS model archives on demand.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../tts/sherpa_catalog.dart';

/// Resolves voice file paths under a models dir and downloads/extracts the
/// `.tar.bz2` archives (plus any separate Matcha vocoder). Installing an engine
/// downloads every language voice it bundles.
class SherpaModelInstaller {
  /// Root models directory.
  final String modelsDir;

  /// HTTP client for downloads.
  final http.Client client;

  SherpaModelInstaller({required this.modelsDir, required this.client});

  /// Directory holding all sherpa models.
  String get root => p.join(modelsDir, 'sherpa');

  /// The extracted directory for [voice].
  String dirOf(SherpaVoice voice) => p.join(root, voice.dirName);

  /// Absolute path to a voice's main model file.
  String modelPath(SherpaVoice voice) => p.join(dirOf(voice), voice.modelFile);

  /// Absolute path to a relative file within the voice dir ('' stays '').
  String fileIn(SherpaVoice voice, String relative) =>
      relative.isEmpty ? '' : p.join(dirOf(voice), relative);

  /// Absolute vocoder path (Matcha), or '' if none.
  String vocoderPath(SherpaVoice voice) =>
      voice.vocoderFile.isEmpty ? '' : p.join(dirOf(voice), voice.vocoderFile);

  /// Whether a single [voice] (and its vocoder, if any) is downloaded.
  bool isVoiceInstalled(SherpaVoice voice) {
    if (!File(modelPath(voice)).existsSync()) return false;
    if (voice.vocoderFile.isNotEmpty && !File(vocoderPath(voice)).existsSync()) {
      return false;
    }
    return true;
  }

  /// Whether every voice of [model] is installed.
  bool isInstalled(SherpaModel model) =>
      model.voices.every(isVoiceInstalled);

  /// Deletes every voice directory of [model] from disk. Best-effort.
  void uninstall(SherpaModel model) {
    for (final voice in model.voices) {
      final dir = Directory(dirOf(voice));
      if (dir.existsSync()) {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Non-fatal: a locked/partial dir just stays.
        }
      }
    }
  }

  /// Downloads + extracts every missing voice of [model], streaming log lines.
  /// [onProgress] reports overall completion (0–1) across all of the model's
  /// voices as bytes arrive.
  Stream<String> ensureInstalled(
    SherpaModel model, {
    void Function(double fraction)? onProgress,
  }) async* {
    Directory(root).createSync(recursive: true);
    final total = model.voices.length;
    for (var i = 0; i < model.voices.length; i++) {
      final voice = model.voices[i];
      final langs = voice.languages.map((l) => l.toUpperCase()).join('/');
      // Map a single voice's [0,1] download onto the overall bar.
      void report(double f) => onProgress?.call((i + f) / total);
      if (File(modelPath(voice)).existsSync()) {
        yield '${model.label} ($langs) already installed.';
        report(1);
      } else {
        yield 'Downloading ${model.label} ($langs, ~${voice.sizeMb} MB)…';
        final bytes = await _download(voice.archiveUrl, onProgress: report);
        yield 'Extracting ${model.label} ($langs)…';
        // bzip2 + tar decode is CPU-heavy and synchronous → run off-isolate so
        // the UI stays responsive.
        final dest = root;
        await Isolate.run(() => extractTarBz2(bytes, dest));
        yield '${model.label} ($langs) installed.';
      }
      if (voice.vocoderFile.isNotEmpty &&
          !File(vocoderPath(voice)).existsSync()) {
        yield 'Downloading vocoder…';
        await File(vocoderPath(voice))
            .writeAsBytes(await _download(voice.vocoderUrl));
        yield 'Vocoder installed.';
      }
    }
    onProgress?.call(1);
    yield '${model.label} is ready.';
  }

  /// Streams a download with byte-level [onProgress] (0–1) and retries on
  /// transient network failures (GitHub's release CDN drops connections under
  /// load, especially for large files).
  Future<Uint8List> _download(
    String url, {
    void Function(double fraction)? onProgress,
    int maxAttempts = 4,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final resp = await client.send(http.Request('GET', Uri.parse(url)));
        if (resp.statusCode != 200) {
          throw HttpException('HTTP ${resp.statusCode} for $url');
        }
        final total = resp.contentLength ?? 0;
        final builder = BytesBuilder(copy: false);
        var received = 0;
        await for (final chunk in resp.stream) {
          builder.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
        return builder.toBytes();
      } on Object catch (e) {
        lastError = e;
        if (attempt < maxAttempts) {
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
    throw HttpException('Download failed after $maxAttempts attempts: $lastError');
  }
}

/// Extracts a `.tar.bz2` archive into [destDir]. Top-level so it can run inside
/// `Isolate.run` (bzip2 + tar decode is CPU-heavy and synchronous).
void extractTarBz2(Uint8List bytes, String destDir) {
  final tar = BZip2Decoder().decodeBytes(bytes);
  final archive = TarDecoder().decodeBytes(tar);
  for (final entry in archive) {
    if (!entry.isFile) continue;
    final out = File(p.join(destDir, entry.name));
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(entry.content as List<int>);
  }
}
