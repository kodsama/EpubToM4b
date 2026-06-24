# Driving Audiobook Studio from an agent

The converter is usable headlessly via a Dart CLI that reuses the app's engine
(EPUB parsing, local sherpa-onnx TTS, ffmpeg assembly, model downloads). It is
designed to be discovered and driven programmatically.

## Discover the interface

Run `schema` to get a machine-readable JSON description of every command,
option, available model, output event, and exit code:

```bash
audiobook_studio schema
```

(For clean stdout, use the compiled binary — see "Build" below. `dart run …`
prints build-hook noise to stdout.)

## Recommended flow

1. `audiobook_studio schema` — learn the interface and the model ids.
2. `audiobook_studio info <book.epub> --json` — title, language, chapters.
3. `audiobook_studio list-models --json` — see which models are installed.
4. `audiobook_studio download <modelId>` — if a local model is needed.
5. `audiobook_studio convert <book.epub> --json [options]` — convert.

## Output contract (`--json`)

Every command with `--json` emits one JSON object per line on stdout:

- `{"event":"log","message":...}`
- `{"event":"progress","phase":"download|synthesize","fraction":0..1}`
- `{"event":"done","output":"<path>","chapters":N}`
- `{"event":"error","message":...}` (on stderr; process exits non-zero)

Exit code `0` = success, `1` = error.

## Engines

- `--engine local` (default): free, offline. Needs a downloaded model
  (`--model <id>`, default = best for the book's language). Recommended: `piper`.
- `--engine openai` / `elevenlabs`: needs `--api-key` or `OPENAI_API_KEY` /
  `ELEVENLABS_API_KEY`.

## Build a standalone binary (recommended for agents)

```bash
cd app
dart build cli      # → build/cli/<platform>/bundle/bin/audiobook_studio
```

The local engine loads sherpa-onnx's native library from a `flutter build macos`
output (auto-detected) or `--sherpa-lib <dir>`.

## Example

```bash
EXE=app/build/cli/macos_arm64/bundle/bin/audiobook_studio
$EXE convert book.epub --engine local --model piper --json
# → …{"event":"done","output":"/path/Book.m4b","chapters":27}
```
