# Audiobook Studio

A cross-platform **Flutter app** for **macOS · Windows · Linux · Android · iOS**
that turns a DRM-free **EPUB** into a chaptered **`.m4b` audiobook** — with a
modern GUI, one-click model downloads, pluggable text-to-speech engines,
multi-language narration, and live global + per-chapter progress. It also ships
a headless **CLI** and an **MCP server** (desktop) for terminals and AI clients.

**No Python at runtime** — all logic is Dart. On desktop the app orchestrates the
system `ffmpeg`; on Android/iOS ffmpeg is bundled in-process (ffmpeg-kit, audio
build) and the finished file is delivered via the share sheet. Local TTS is
sherpa-onnx (offline); cloud TTS is OpenAI / ElevenLabs over HTTP.

---

## Features

- 📖 **Pick an EPUB** from a native file browser; metadata, cover, and a
  per-chapter include/exclude checklist are shown instantly.
- 🔎 **Dependency check + one-click install** — the app detects what's missing
  for the selected engine and installs system packages via your platform's
  package manager (Homebrew / apt / winget), streaming the log live.
- 🗣️ **Three engines**, selectable in the UI:
  | Engine | Cost | Locale | Notes |
  |---|---|---|---|
  | **Local** (default) | free | offline | sherpa-onnx running any of many models — see below |
  | **OpenAI** | paid | cloud | `gpt-4o-mini-tts`, very natural |
  | **ElevenLabs** | paid | cloud | `eleven_multilingual_v2`, top fidelity |
- 🧠 **Many state-of-the-art local models** (one unified engine via sherpa-onnx),
  auto-downloaded on demand: **Piper/VITS** (incl. French Siwis), **MMS**
  (1000+ languages), **Kokoro** (multilingual), **Matcha**, **Kitten**. Verified
  producing French audio on macOS. No Python — sherpa-onnx bundles its own
  runtime and phonemizer.
- 🌍 **Multi-language** — French and English out of the box; extend by adding a
  voice to `lib/data/tts/voice_catalog.dart`.
- 🎚️ **All options in the UI with smart defaults** — engine, language, voice,
  speed, bitrate, cover override, API keys, output filename and destination.
- 🖼️ **Cover art** — provide your own image or let it use the EPUB's embedded
  cover automatically.
- 📊 **Live progress** — a character-weighted global bar plus a per-chapter row
  with status and its own mini bar.
- ♻️ **Resumable** — finished chapters are cached in a `.work/` folder next to
  the output; re-running skips them.
- 📜 **Full logs** — every command and event, copyable to the clipboard.

---

## Install & run (development)

Prerequisites: [Flutter](https://docs.flutter.dev/get-started/install) 3.41+ with
desktop support enabled.

```bash
cd app
flutter pub get
flutter run -d macos      # or -d linux / -d windows
```

### Runtime dependencies (installed from within the app)

The app's **step 2** checks these and offers to install the missing ones:

| Dependency | macOS | Linux | Windows |
|---|---|---|---|
| ffmpeg / ffprobe | `brew install ffmpeg` | `apt-get install ffmpeg` | `winget install Gyan.FFmpeg` |
| espeak-ng (Kokoro) | `brew install espeak-ng` | `apt-get install espeak-ng` | `winget install eSpeak-NG.eSpeak-NG` |
| piper binary + voice | **auto-downloaded in-app on Linux/Windows** from [rhasspy/piper](https://github.com/rhasspy/piper) + [piper-voices](https://huggingface.co/rhasspy/piper-voices) |||

Cloud engines (OpenAI / ElevenLabs) need no local install — just paste an API
key into the options panel.

> **Piper on macOS:** upstream's standalone macOS release is currently broken
> (the "aarch64" asset ships an x86_64 binary and omits its bundled libraries),
> and the maintained fork distributes Python wheels only. So in-app Piper
> auto-install is enabled on **Linux/Windows** but not macOS yet. On macOS use a
> cloud engine, or install a working `piper` on your `PATH` manually. The app
> detects this and shows an honest note instead of a broken download.

---

## How to use

1. **Choose your book** — browse for a `.epub`. Review the chapter list and
   untick anything you don't want narrated (e.g. endnotes).
2. **Check your toolkit** — if anything's missing, click *Install missing
   packages* and watch the log.
3. **Tune the narration** — pick the engine, language, and voice; adjust speed
   and bitrate; optionally override the cover; set the output filename and
   folder. Defaults are sensible (Piper, the book's language, 1.0×, 128 kbps).
4. **Create the audiobook** — click *Convert to M4B*. Follow the global and
   per-chapter progress. Cancel any time; finished chapters are cached so you
   can resume.

---

## Command line (terminal / LLM)

The same engine is usable headless via a Dart CLI — handy for scripts or driving
from an LLM. It reuses the app's data layer (no Flutter), and local TTS runs in
pure Dart by loading sherpa-onnx's native library from a `flutter build macos`
output (auto-detected, or pass `--sherpa-lib`).

```bash
cd app
dart run audiobook_studio info book.epub          # metadata + chapters
dart run audiobook_studio list-models             # engines, sizes, install state
dart run audiobook_studio download piper          # fetch a local model
dart run audiobook_studio convert book.epub \
    --engine local --model piper --speed 1.0 -o out.m4b

# Cloud engine (no local model needed):
OPENAI_API_KEY=sk-... dart run audiobook_studio convert book.epub --engine openai

# Machine-readable output for scripts / LLMs:
dart run audiobook_studio convert book.epub --json
```

`--json` emits one JSON object per line (`log` / `progress` / `done` / `error`),
so a caller can track progress and the final output path programmatically. Run
`dart run audiobook_studio --help` for all options.

For a clean, standalone binary (recommended for scripts/LLMs — `dart run` prints
build-hook noise to stdout), compile it once:

```bash
dart build cli                                   # → build/cli/<platform>/bundle/bin/audiobook_studio
build/cli/macos_arm64/bundle/bin/audiobook_studio convert book.epub --json
```

The local engine loads sherpa-onnx's native library from a `flutter build macos`
output (auto-detected), or pass `--sherpa-lib <dir>` to point at it explicitly.

### For agents

`audiobook_studio schema` prints a JSON description of every command, option,
model, output event and exit code — an agent can learn the whole interface in
one call. For AI clients, `audiobook_studio mcp` runs a **Model Context Protocol**
server over stdio exposing `get_book_info`, `list_models`, `download_model` and
`convert_audiobook`. See [`../AGENTS.md`](../AGENTS.md) for registration, the
recommended flow and the `--json` event contract.

## License

GPL-3.0 (see [`../LICENSE`](../LICENSE)). All bundled dependencies are
GPL-compatible; runtime-downloaded model weights carry their own licenses (note:
MMS voices are CC-BY-NC / non-commercial). See
[`../THIRD_PARTY_LICENSES.md`](../THIRD_PARTY_LICENSES.md).

## Development

```bash
flutter analyze      # static analysis — must be clean
flutter test         # unit + widget tests
```

The codebase is layered (UI → controllers → data → domain) and every layer is
unit-tested with fakes injected at the seams (`ProcessRunner`, `TtsBackend`,
`FfmpegService`, `http.Client`). See [ARCHITECTURE.md](ARCHITECTURE.md) for the
module map and how to add a new backend or language.

---

## Not yet supported (documented follow-ups)

- `.mobi` / `.azw` input (EPUB only for now).
- iOS distribution: CI builds an **unsigned** `.ipa`; installing on a device
  needs re-signing with an Apple Developer identity.
- On-device (Android/iOS) conversion is wired and compiles in CI, but end-to-end
  runtime hasn't been exercised on physical hardware.
- Web target; cloud cost estimation in the UI.
