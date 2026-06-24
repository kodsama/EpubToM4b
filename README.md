# Audiobook Studio (EpubToM4b)

[![CI](https://github.com/kodsama/EpubToM4b/actions/workflows/ci.yml/badge.svg)](https://github.com/kodsama/EpubToM4b/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

Turn a DRM-free **EPUB** into a chaptered **`.m4b` audiobook** — chapters,
title/author tags and cover art embedded, so it shows up properly in Apple
Books, VLC, BookPlayer, Smart AudioBook Player, etc.

Two ways to use it:

| | What | Where |
|---|---|---|
| 🖥️📱 **Audiobook Studio** | Flutter app for **macOS · Windows · Linux · Android · iOS** **+ a headless CLI** (desktop), with offline local TTS (sherpa-onnx: Piper/VITS, MMS, Kokoro, Matcha, Kitten) and cloud TTS (OpenAI / ElevenLabs). Modern stepped UI, one-click model downloads, terminal/agent-friendly CLI. | [`app/`](app/) → [README](app/README.md) |
| 🐍 **`epub_to_m4b.py`** | The original single-file Python CLI (Kokoro/Piper/OpenAI/ElevenLabs). | [`epub_to_m4b.py`](epub_to_m4b.py) |

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

## Docs

- App usage & engines: [`app/README.md`](app/README.md)
- Architecture: [`app/ARCHITECTURE.md`](app/ARCHITECTURE.md)
- Driving it from an agent: [`AGENTS.md`](AGENTS.md)
- Design/specs history: [`docs/superpowers/`](docs/superpowers/)

## License

**GPL-3.0** — see [`LICENSE`](LICENSE). All bundled dependencies are
GPL-compatible; runtime-downloaded model weights carry their own licenses (note:
MMS voices are CC-BY-NC / non-commercial). Details in
[`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md).

---

## The Python CLI (`epub_to_m4b.py`)

The original single-file converter. TTS is pluggable (free/local or paid/cloud).

```bash
# system deps
brew install ffmpeg espeak-ng          # Linux: apt install ffmpeg espeak-ng
# python deps
pip install -r requirements.txt
pip install "kokoro>=0.9" "misaki[fr]"  # local TTS

python epub_to_m4b.py book.epub --backend kokoro --voice ff_siwis
```

See the header of [`epub_to_m4b.py`](epub_to_m4b.py) for all backends and flags
(`--backend kokoro|openai|elevenlabs|piper`, `--voice`, `--speed`, `--bitrate`,
`--cover`, `--limit`, `-o`). The run is resumable (finished chapters are cached
in a `.work/` folder).
