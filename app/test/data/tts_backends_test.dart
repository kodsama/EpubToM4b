import 'dart:io';
import 'dart:typed_data';

import 'package:audiobook_studio/data/audio/wav_writer.dart';
import 'package:audiobook_studio/data/deps/kokoro_installer.dart';
import 'package:audiobook_studio/data/process_runner.dart';
import 'package:audiobook_studio/data/tts/backend_factory.dart';
import 'package:audiobook_studio/data/tts/elevenlabs_backend.dart';
import 'package:audiobook_studio/data/tts/kokoro_backend.dart';
import 'package:audiobook_studio/data/tts/openai_backend.dart';
import 'package:audiobook_studio/data/tts/piper_backend.dart';
import 'package:audiobook_studio/domain/book.dart';
import 'package:audiobook_studio/domain/conversion_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

/// Captures the last invocation so tests can assert argv and stdin.
class RecordingRunner extends ProcessRunner {
  String? exe;
  List<String>? args;
  String? stdin;

  @override
  Future<ProcessRunResult> run(String e, List<String> a, {String? stdinText}) async {
    exe = e;
    args = a;
    stdin = stdinText;
    return const ProcessRunResult(0, '', '');
  }

  @override
  Stream<String> stream(String e, List<String> a, {String? stdinText}) =>
      const Stream.empty();
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('tts_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('PiperBackend', () {
    test('invokes piper with model, length_scale and pipes text via stdin', () async {
      final runner = RecordingRunner();
      final out = p.join(tmp.path, 'o.wav');
      await PiperBackend(runner: runner, modelPath: '/voices/fr.onnx', speed: 2.0)
          .synth('Bonjour', out);

      expect(runner.exe, 'piper');
      expect(runner.args, containsAllInOrder(['--model', '/voices/fr.onnx']));
      expect(runner.args, containsAllInOrder(['--output_file', out]));
      // speed 2.0 -> length_scale 0.5
      final ls = runner.args![runner.args!.indexOf('--length_scale') + 1];
      expect(double.parse(ls), 0.5);
      expect(runner.stdin, 'Bonjour');
    });
  });

  group('OpenAiBackend', () {
    test('POSTs model/voice/input and writes the WAV body', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response.bytes(
            Uint8List.fromList([1, 2, 3]), 200);
      });
      final out = p.join(tmp.path, 'o.wav');
      await OpenAiBackend(client: client, apiKey: 'sk-x', voice: 'nova')
          .synth('Hello', out);

      expect(captured.method, 'POST');
      expect(captured.headers['Authorization'], 'Bearer sk-x');
      expect(captured.body, contains('"voice":"nova"'));
      expect(captured.body, contains('"input":"Hello"'));
      expect(File(out).readAsBytesSync(), [1, 2, 3]);
    });

    test('throws on non-200', () async {
      final client = MockClient((req) async => http.Response('nope', 401));
      expect(
        () => OpenAiBackend(client: client, apiKey: 'bad')
            .synth('x', p.join(tmp.path, 'o.wav')),
        throwsA(isA<HttpException>()),
      );
    });
  });

  group('ElevenLabsBackend', () {
    test('wraps returned PCM into a valid WAV header', () async {
      final pcm = Uint8List.fromList(List<int>.filled(8, 7));
      final client = MockClient((req) async {
        expect(req.url.path, contains('voice-123'));
        expect(req.headers['xi-api-key'], 'el-key');
        return http.Response.bytes(pcm, 200);
      });
      final out = p.join(tmp.path, 'o.wav');
      await ElevenLabsBackend(client: client, apiKey: 'el-key', voiceId: 'voice-123')
          .synth('Salut', out);

      final bytes = File(out).readAsBytesSync();
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      // header (44 bytes) + pcm payload
      expect(bytes.length, 44 + pcm.length);
    });
  });

  group('buildWavPcm16Mono', () {
    test('produces a 44-byte header and correct data size', () {
      final pcm = Uint8List.fromList(List<int>.filled(100, 0));
      final wav = buildWavPcm16Mono(pcm, 22050);
      expect(wav.length, 44 + 100);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    });
  });

  group('makeBackend', () {
    Book b() => const Book(title: 't', author: 'a', languageCode: 'fr', chapters: [
          Chapter(index: 0, title: 'c', text: 'hello world this is text'),
        ]);
    ConversionOptions o(TtsBackendKind k) => ConversionOptions.defaults(
          b(),
          outputPath: '/o.m4b',
          workDir: '/w',
        ).copyWith(backend: k, voiceId: 'v', apiKeys: {'openai': 'k', 'elevenlabs': 'k'});

    test('returns the right type per backend kind', () {
      final runner = RecordingRunner();
      final client = MockClient((_) async => http.Response('', 200));
      expect(
          makeBackend(o(TtsBackendKind.piper),
              runner: runner, httpClient: client, modelsDir: '/m'),
          isA<PiperBackend>());
      expect(
          makeBackend(o(TtsBackendKind.openai),
              runner: runner, httpClient: client, modelsDir: '/m'),
          isA<OpenAiBackend>());
      expect(
          makeBackend(o(TtsBackendKind.elevenlabs),
              runner: runner, httpClient: client, modelsDir: '/m'),
          isA<ElevenLabsBackend>());
    });

    test('Kokoro builds a KokoroBackend when an installer is provided', () {
      final runner = RecordingRunner();
      final client = MockClient((_) async => http.Response('', 200));
      final kokoro = KokoroInstaller(modelsDir: '/m', client: client);
      expect(
        makeBackend(o(TtsBackendKind.kokoro),
            runner: runner, httpClient: client, modelsDir: '/m', kokoro: kokoro),
        isA<KokoroBackend>(),
      );
    });
  });
}
