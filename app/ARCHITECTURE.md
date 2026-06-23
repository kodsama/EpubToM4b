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

## §Kokoro — the one backend needing real-hardware wiring

`KokoroBackend` is structured like the others:

- **Phonemization** uses `espeak-ng` through `ProcessRunner` (unit-tested by
  asserting the argv).
- **Inference** is hidden behind a `KokoroSession` interface so the ONNX runtime
  is an injectable dependency. A production `OrtKokoroSession` wraps the
  `onnxruntime` package (Dart FFI) and the downloaded `kokoro.onnx` model +
  voice pack.
- **Output** wraps the model's float PCM via `wav_writer`.

What remains to verify on real hardware: bundling the `onnxruntime` native
library per platform, the phoneme→token vocabulary mapping for the exact model
revision, and running inference in a background isolate. Until then, selecting
Kokoro surfaces a clear message rather than failing silently.
