import 'dart:io';

import 'package:audiobook_studio/data/process_runner.dart';
import 'package:audiobook_studio/data/tts/kokoro_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Returns canned espeak IPA output and records the invocation.
class EspeakRunner extends ProcessRunner {
  String? exe;
  List<String>? args;
  String? stdin;
  final String ipa;
  EspeakRunner(this.ipa);

  @override
  Future<ProcessRunResult> run(String e, List<String> a, {String? stdinText}) async {
    exe = e;
    args = a;
    stdin = stdinText;
    return ProcessRunResult(0, ipa, '');
  }

  @override
  Stream<String> stream(String e, List<String> a, {String? stdinText}) =>
      const Stream.empty();
}

/// Fake inference that returns a fixed number of samples.
class FakeSession extends KokoroSession {
  List<int>? lastTokens;
  @override
  int get sampleRate => 24000;
  @override
  Future<List<double>> infer(List<int> tokens, String voiceId, double speed) async {
    lastTokens = tokens;
    return List<double>.filled(120, 0.5);
  }
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('kokoro_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('phonemize invokes espeak-ng -q --ipa -v <lang> with text on stdin', () async {
    final runner = EspeakRunner('bɔ̃ʒuʁ');
    final backend = KokoroBackend(
      runner: runner,
      session: FakeSession(),
      languageCode: 'fr',
      voiceId: 'ff_siwis',
    );
    final phonemes = await backend.phonemize('Bonjour');

    expect(runner.exe, 'espeak-ng');
    expect(runner.args, containsAllInOrder(['-q', '--ipa']));
    expect(runner.args, containsAllInOrder(['-v', 'fr-fr'])); // fr -> espeak fr-fr
    expect(runner.stdin, 'Bonjour');
    expect(phonemes, isNotEmpty);
  });

  test('synth writes a valid WAV at the session sample rate', () async {
    final session = FakeSession();
    final backend = KokoroBackend(
      runner: EspeakRunner('hɛloʊ'),
      session: session,
      languageCode: 'en',
      voiceId: 'af_heart',
    );
    final out = p.join(tmp.path, 'o.wav');
    await backend.synth('Hello', out);

    final bytes = File(out).readAsBytesSync();
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    // 120 float samples -> 240 PCM bytes + 44-byte header.
    expect(bytes.length, 44 + 240);
    expect(backend.sampleRate, 24000);
    expect(session.lastTokens, isNotEmpty); // phonemes were tokenized
  });

  group('KokoroVocab', () {
    test('tokenizes known symbols and drops unknown ones', () {
      final vocab = KokoroVocab.fallback();
      final tokens = vocab.tokenize('ab█'); // █ is not in the vocab
      expect(tokens.length, 2); // a, b mapped; block dropped
      expect(tokens.every((t) => t > 0), isTrue);
    });
  });
}
