<p align="center">
  <img src="app/assets/logo.png" alt="Audiobook Studio logo" width="160">
</p>

<h1 align="center">Audiobook Studio</h1>

<p align="center">
  <a href="https://github.com/kodsama/AudiobookStudio/actions/workflows/ci.yml"><img src="https://github.com/kodsama/AudiobookStudio/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPLv3-blue.svg" alt="License: GPL v3"></a>
</p>

Turn a DRM-free **EPUB** into a chaptered **`.m4b` audiobook** — chapters,
title/author tags and cover art embedded, so it shows up properly in Apple
Books, VLC, BookPlayer, Smart AudioBook Player, etc.

**Audiobook Studio** is a Flutter app for **macOS · Windows · Linux · Android ·
iOS** **plus a headless CLI** (desktop), with offline local TTS (sherpa-onnx:
Piper/VITS, MMS, Kokoro, Matcha, Kitten) and cloud TTS (OpenAI / ElevenLabs). It
has a modern stepped UI, one-click model downloads and a terminal/agent-friendly
CLI — see [`app/`](app/) and its [README](app/README.md).

On desktop the app drives the system **ffmpeg**; on Android/iOS ffmpeg is bundled
in-process (ffmpeg-kit) and the finished `.m4b` is delivered via the share sheet.
Each tagged release publishes native packages: `.dmg` (macOS), `.exe` (Windows),
`.deb`/`.rpm`/`.AppImage` (Linux), `.apk`/`.aab` (Android) and an **unsigned**
`.ipa` (iOS — must be re-signed with an Apple identity to install on a device).

## Quick start — the app

```bash
cd app
flutter pub get
flutter run -d macos          # or -d linux / -d windows / -d <android|ios device>
```

Then follow the on-screen steps: **check the toolkit** (install a free local
voice like *Piper*, or add a cloud API key) → **choose your EPUB** → **tune the
narration** → **convert**.

## Quick start — the CLI (terminal / agents)

```bash
cd app
dart run audiobook_studio info book.epub
dart run audiobook_studio convert book.epub --engine local --model piper --json
```

`audiobook_studio schema` prints a JSON description of the whole interface for
agents. See [`AGENTS.md`](AGENTS.md) and [`app/README.md`](app/README.md).

## Use it from an AI assistant (MCP server)

Audiobook Studio has a built-in **Model Context Protocol** server, so an AI
client can drive conversions directly. It exposes four tools:

| Tool | What it does |
|---|---|
| `get_book_info` | title, author, language, cover, chapters of an EPUB |
| `list_models` | local TTS models + install state |
| `download_model` | fetch a local model for offline use |
| `convert_audiobook` | convert an EPUB to a chaptered `.m4b` |

Start it (stdio transport):

```bash
cd app
dart run audiobook_studio mcp        # dev — or use the bundled binary in any release
```

Register it with an MCP client (Claude Code, Claude Desktop, …):

```json
{
  "mcpServers": {
    "audiobook-studio": {
      "command": "/path/to/audiobook_studio",
      "args": ["mcp"]
    }
  }
}
```

The `audiobook_studio` binary is bundled inside every desktop package (e.g.
`Audiobook Studio.app/Contents/Resources/cli/bin/` on macOS). In Claude Code:
`claude mcp add audiobook-studio /path/to/audiobook_studio mcp`.

## Docs

- App usage & engines: [`app/README.md`](app/README.md)
- Architecture: [`app/ARCHITECTURE.md`](app/ARCHITECTURE.md)
- Driving it from an agent: [`AGENTS.md`](AGENTS.md)

## License

**GPL-3.0** — see [`LICENSE`](LICENSE). All bundled dependencies are
GPL-compatible; runtime-downloaded model weights carry their own licenses (note:
MMS voices are CC-BY-NC / non-commercial). Details in
[`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md).
