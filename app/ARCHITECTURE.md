# Architecture

Audiobook Studio is a layered Flutter desktop app. Dependencies point **inward**:
UI depends on controllers, controllers on data services, data on domain models.
Domain models depend on nothing. Every cross-layer boundary is an interface or a
plain value type, so each unit is testable in isolation with a fake.

```
┌───────────────────────────── UI (lib/ui) ─────────────────────────────┐
│ HomeScreen → SectionCard, FilePickerCard, DependencyCard, OptionsPanel, │
│ ConvertBar, ProgressView, LogConsole         (Flutter widgets only)     │
└───────────────▲────────────────────────────────────────────────────────┘
                │ observes (ChangeNotifier)
┌───────────────┴──────────── Logic (lib/logic) ─────────────────────────┐
│ AppController          – UI-facing state machine / workflow             │
│ ConversionController   – parse→chunk→synth→concat→assemble + progress   │
│ LogController          – central log sink (buffer + stream)             │
└───────────────▲──────────────────────────────────────────────────────-─┘
                │ uses
┌───────────────┴──────────── Data (lib/data) ──────────────────────────┐
│ epub/   OpfReader, ContentCleaner, CoverExtractor, EpubParser          │
│ text/   SentenceSplitter, TextChunker                                  │
│ tts/    TtsBackend (iface) + Piper/OpenAI/ElevenLabs/Kokoro + factory  │
│ audio/  FfmpegService, wav_writer                                      │
│ deps/   DependencyChecker, DependencyInstaller (Mac/Linux/Windows)     │
│ ProcessRunner  – the single seam for running external binaries         │
└───────────────▲──────────────────────────────────────────────────────-┘
                │ produces / consumes
┌───────────────┴──────────── Domain (lib/domain) ──────────────────────┐
│ Book, Chapter · ConversionOptions, TtsBackendKind · ConversionProgress,│
│ ChapterProgress · Dependency*, HostOs · Language, Voice                │
└────────────────────────────────────────────────────────────────────────┘
```

## Key seams (where fakes are injected)

- **`ProcessRunner`** — every `ffmpeg`/`piper`/`espeak-ng`/`brew` call goes
  through it. Tests inject a recording/scripted runner; production uses
  `SystemProcessRunner`.
- **`TtsBackend`** — the one interface all engines implement. The
  `ConversionController` only knows this interface.
- **`FfmpegService`** — overridable; tests subclass it to record calls and write
  placeholder files instead of invoking ffmpeg.
- **`http.Client`** — cloud backends take a client; tests pass `MockClient`.

## Data flow of a conversion

1. `AppController.loadBook(bytes, path)` → `EpubParser.parse` → `Book`; default
   `ConversionOptions` derived; `DependencyChecker.check` runs for the backend.
2. User adjusts options in `OptionsPanel`; `AppController` mutates the immutable
   `ConversionOptions` via `copyWith`.
3. `AppController.startConversion` builds the backend via `makeBackend` and calls
   `ConversionController.run`.
4. Per selected chapter: `TextChunker.chunk` → `backend.synth` per chunk (resume
   skips cached WAVs) → `FfmpegService.concatToChapterWav`. Progress is emitted
   after each chunk (character-weighted).
5. `FfmpegService.assembleM4b` muxes AAC + chapter markers + cover + tags with
   `+faststart`.

## Adding a backend

1. Implement `TtsBackend` in `lib/data/tts/<name>_backend.dart`
   (`sampleRate`, `maxChars`, `supportedLanguages`, `voicesFor`, `synth`).
2. Add its voices to `VoiceCatalog._all`.
3. Add a `case` to `makeBackend` in `backend_factory.dart`.
4. If it needs a binary/model, extend `DependencyKind` + `DependencyChecker`.

No UI or controller code changes — the dropdown and pipeline pick it up.

## Adding a language

Add `Voice` entries with the new `languageCode` for each backend that supports
it, plus a label in `VoiceCatalog.languageLabels`. The language dropdown derives
its options from the catalog.

## §Kokoro — local ONNX engine (implemented & verified on macOS)

`KokoroBackend` runs the Kokoro v1.0 model fully in Dart (no Python):

- **Download** — `KokoroInstaller` fetches the int8 `kokoro.onnx` (~88 MB) and
  `voices.bin` (~27 MB) into the app models dir, with a one-click button.
- **Phonemization** — `espeak-ng` via `ProcessRunner` (`fr`→`fr-fr`,
  `en`→`en-us`), unit-tested by asserting the argv.
- **Tokenization** — the embedded 114-entry vocab (`kokoro_vocab.g.dart`,
  generated from the model's `config.json`).
- **Voices** — `KokoroVoices` parses the npz/npy style tables and selects the
  256-d style row for the (unpadded) token count.
- **Inference** — `KokoroOrtSession` uses `flutter_onnxruntime` (bundled ORT
  1.24 on macOS) with inputs `tokens` (int64), `style` (float32 [1,256]),
  `speed` (float32 [1]) → `audio`. Wrapped to a WAV via `wav_writer`.

Verified end-to-end by an integration test (`integration_test/`) running on
macOS that synthesizes French audio through the real onnxruntime native library.

Platform notes: requires macOS deployment target ≥ 14 and `use_frameworks!
:linkage => :static` in the macOS Podfile (both configured). Inference currently
runs on the main isolate; moving it to a background isolate is a future
optimization.
