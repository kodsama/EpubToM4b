# Driving Audiobook Studio from an agent

The converter is usable headlessly two ways, both reusing the app's engine
(EPUB parsing, local sherpa-onnx TTS, ffmpeg assembly, model downloads):

- a **JSON CLI** (`audiobook_studio <command> --json`), and
- a built-in **MCP server** (`audiobook_studio mcp`) for AI clients.

Both are designed to be discovered and driven programmatically.

## MCP server (for AI clients)

`audiobook_studio mcp` runs a Model Context Protocol server over stdio
(newline-delimited JSON-RPC 2.0). Register it with an MCP client:

```json
{
  "mcpServers": {
    "audiobook-studio": { "command": "/path/to/audiobook_studio", "args": ["mcp"] }
  }
}
```

In Claude Code: `claude mcp add audiobook-studio /path/to/audiobook_studio mcp`.
The `audiobook_studio` binary is bundled in every desktop package (e.g.
`Audiobook Studio.app/Contents/Resources/cli/bin/audiobook_studio` on macOS).

Tools exposed: `get_book_info(path)`, `list_models()`,
`download_model(model_id)`, `convert_audiobook(path, engine?, model?, voice?,
language?, speed?, bitrate?, cover?, chapters?, output?, api_key?)`. Each returns
a JSON text payload; `convert_audiobook` returns `{output, chapters}` when done.

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
