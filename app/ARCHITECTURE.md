# Architecture

Audiobook Studio is a layered Flutter desktop app with a Flutter-free engine, so
the same code powers both the GUI and a headless CLI. Dependencies point
**inward**: UI → controllers → data services → domain models. Domain models
depend on nothing. Every cross-layer boundary is an interface or a plain value
type, so each unit is testable in isolation with a fake.

```
┌──────────────── UI (lib/ui) — Flutter widgets only ────────────────┐
│ HomeScreen (stepped accordion + floating log) → SectionCard,        │
│ DependencyCard, FilePickerCard, OptionsPanel, ConvertBar,           │
│ ProgressView, LogConsole                                            │
└───────────────▲─────────────────────────────────────────────────────┘
                │ observes (ChangeNotifier)
┌───────────────┴──────────── Logic (lib/logic) ─────────────────────┐
│ AppController        – UI-facing state machine / workflow           │
│ ConversionController – parse→chunk→synth→concat→assemble + progress │
│ LogController        – central log sink (buffer + stream)           │
└───────────────▲─────────────────────────────────────────────────────┘
                │ uses (Flutter-free below this line)
┌───────────────┴──────────── Data (lib/data) ───────────────────────┐
│ epub/   OpfReader · ContentCleaner · CoverExtractor · EpubParser    │
│ text/   SentenceSplitter · TextChunker                              │
│ tts/    TtsBackend (iface) · SherpaTtsBackend (local, all families) │
│         · OpenAiBackend · ElevenLabsBackend · backend_factory       │
│         · sherpa_catalog · voice_catalog                            │
│ audio/  FfmpegService · wav_writer                                  │
│ deps/   DependencyChecker · DependencyInstaller · SherpaModelInstaller│
│ ProcessRunner — the single seam for running external binaries       │
└───────────────▲─────────────────────────────────────────────────────┘
                │ produces / consumes
┌───────────────┴──────────── Domain (lib/domain) ───────────────────┐
│ Book · Chapter · ConversionOptions · TtsBackendKind ·               │
│ ConversionProgress · ChapterProgress · Dependency* · HostOs ·       │
│ Language · Voice                                                    │
└──────────────────────────────────────────────────────────────────────┘

bin/audiobook_studio.dart — CLI; reuses the Data layer directly (no Flutter).
```

## Engines

- **Local** (`TtsBackendKind.local`) — one engine, `SherpaTtsBackend`, powered by
  the `sherpa_onnx` package (bundles onnxruntime + phonemizer; no Python). It
  runs every model family (VITS/Piper, MMS, Kokoro, Matcha, Kitten). Models are
  listed in `sherpa_catalog.dart` and downloaded by `SherpaModelInstaller`.
- **Cloud** — `OpenAiBackend`, `ElevenLabsBackend` (HTTP; need an API key).

## Concurrency (keeping the UI responsive)

Heavy, synchronous work never runs on the UI isolate:

- **Inference** runs in a persistent **worker isolate** (`SherpaTtsBackend`):
  the model loads once there and each `synth` is a message round-trip returning
  ready WAV bytes. The backend is disposed (isolate killed) after a run.
- **Archive extraction** (bzip2/tar) runs in `Isolate.run`.
- **ffmpeg/ffprobe** run as separate processes via `ProcessRunner`.

## Key seams (where fakes are injected)

- **`ProcessRunner`** — every `ffmpeg`/`ffprobe`/`brew` call goes through it;
  tests inject a scripted runner, production uses `SystemProcessRunner`.
- **`TtsBackend`** — the one interface all engines implement; the controller and
  CLI only know this interface.
- **`FfmpegService`** — overridable; tests subclass it to record calls.
- **`http.Client`** — cloud backends + installers take a client; tests pass
  `MockClient`.

## Data flow of a conversion

1. `loadBook(bytes, path)` → `EpubParser.parse` → `Book`; default
   `ConversionOptions` derived; `DependencyChecker.checkAll` probes ffmpeg/ffprobe.
2. Options adjusted in the UI (or CLI flags) → immutable `ConversionOptions`.
3. `makeBackend(options, …)` builds the engine; `ConversionController.run`
   (GUI) or the CLI loop drives it.
4. Per selected chapter: `TextChunker.chunk` → `backend.synth` per chunk (resume
   skips cached WAVs) → `FfmpegService.concatToChapterWav`. Character-weighted
   progress is emitted.
5. `FfmpegService.assembleM4b` muxes AAC + chapter markers + cover + tags with
   `+faststart`.

## Extending

- **Add a local model/voice:** add a `SherpaModel` (with its per-language
  `SherpaVoice`s) to `kSherpaModels` in `sherpa_catalog.dart`. The installer,
  UI list, options dropdown and CLI pick it up automatically.
- **Add a cloud backend:** implement `TtsBackend`, add a `case` to
  `makeBackend`, and add its voices to `VoiceCatalog`.

## macOS platform notes

`sherpa_onnx` requires deployment target ≥ 15 and
`use_frameworks! :linkage => :static` in `macos/Podfile` (both configured).
Verified by `integration_test/sherpa_tts_test.dart`, which synthesizes French
audio through the worker-isolate backend on a real macOS build.
```
