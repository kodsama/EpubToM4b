/// Downloads and extracts sherpa-onnx TTS model archives on demand.
library;

import 'dart:io';
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

  /// Downloads + extracts every missing voice of [model], streaming progress.
  Stream<String> ensureInstalled(SherpaModel model) async* {
    Directory(root).createSync(recursive: true);
    for (final voice in model.voices) {
      final langs = voice.languages.map((l) => l.toUpperCase()).join('/');
      if (File(modelPath(voice)).existsSync()) {
        yield '${model.label} ($langs) already installed.';
      } else {
        yield 'Downloading ${model.label} ($langs, ~${voice.sizeMb} MB)…';
        _extractTarBz2(await _download(voice.archiveUrl), root);
        yield '${model.label} ($langs) installed.';
      }
      if (voice.vocoderFile.isNotEmpty &&
          !File(vocoderPath(voice)).existsSync()) {
        yield 'Downloading vocoder…';
        File(vocoderPath(voice)).writeAsBytesSync(await _download(voice.vocoderUrl));
        yield 'Vocoder installed.';
      }
    }
    yield '${model.label} is ready.';
  }

  /// Extracts a `.tar.bz2` archive into [destDir].
  void _extractTarBz2(Uint8List bytes, String destDir) {
    final tar = BZip2Decoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(tar);
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final out = File(p.join(destDir, entry.name));
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(entry.content as List<int>);
    }
  }

  Future<Uint8List> _download(String url) async {
    final resp = await client.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw HttpException('Download failed (${resp.statusCode}): $url');
    }
    return resp.bodyBytes;
  }
}
