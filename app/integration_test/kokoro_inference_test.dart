// Runs REAL Kokoro ONNX inference inside the macOS app to verify onnxruntime
// works on this platform and the full pipeline produces French audio.
//
// Requires the model + voices pre-downloaded to the scratchpad paths below.
// Run with: flutter test integration_test/kokoro_inference_test.dart -d macos
import 'dart:io';

import 'package:audiobook_studio/data/process_runner.dart';
import 'package:audiobook_studio/data/tts/kokoro_backend.dart';
import 'package:audiobook_studio/data/tts/kokoro_ort_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _scratch =
    '/private/tmp/claude-501/-Users-alexandremartins-Developer-EpubToM4b/7496ede6-f7e9-479b-a9fc-f27224df3676/scratchpad';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Kokoro synthesizes French audio via onnxruntime on macOS',
      (tester) async {
    final model = '$_scratch/kokoro.onnx';
    final voices = '$_scratch/voices.bin';
    if (!File(model).existsSync() || !File(voices).existsSync()) {
      markTestSkipped('model/voices not downloaded');
      return;
    }
    final backend = KokoroBackend(
      runner: SystemProcessRunner(),
      session: KokoroOrtSession(modelPath: model, voicesPath: voices),
      languageCode: 'fr',
      voiceId: 'ff_siwis',
    );
    final out = '$_scratch/kokoro_dart.wav';
    await backend.synth('Bonjour, ceci est un test de synthèse vocale.', out);

    final f = File(out);
    expect(f.existsSync(), isTrue);
    // WAV header (44 bytes) + several seconds of 24 kHz 16-bit mono audio.
    expect(f.lengthSync(), greaterThan(44 + 24000 * 2),
        reason: 'expected > ~0.5s of audio');
  });
}
