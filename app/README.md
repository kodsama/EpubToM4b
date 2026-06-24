# Audiobook Studio

A cross-platform **Flutter desktop app** (macOS / Linux / Windows) that turns a
DRM-free **EPUB** into a chaptered **`.m4b` audiobook** — with a modern GUI,
one-click dependency installation, pluggable text-to-speech engines,
multi-language narration, and live global + per-chapter progress.

It is the GUI successor to the project's original `epub_to_m4b.py` CLI. **No
Python at runtime** — all logic is Dart; the app orchestrates a few native
binaries (`ffmpeg`, `piper`, `espeak-ng`) and cloud TTS over HTTP.

> **Status / verification note:** the macOS path is fully built and verified on
> the development machine. The Linux/Windows installer paths and the Kokoro
> ONNX backend are implemented against the same interfaces and unit-tested with
> fakes, but need verification on real Linux/Windows hardware and with the
> Kokoro runtime wired in (see [ARCHITECTURE.md](ARCHITECTURE.md) §Kokoro).

---

## Features

- 📖 **Pick an EPUB** from a native file browser; metadata, cover, and a
  per-chapter include/exclude checklist are shown instantly.
- 🔎 **Dependency check + one-click install** — the app detects what's missing
  for the selected engine and installs system packages via your platform's
  package manager (Homebrew / apt / winget), streaming the log live.
- 🗣️ **Four TTS engines behind one interface**, selectable in the UI:
  | Engine | Cost | Locale | Notes |
  |---|---|---|---|
  | **Piper** (default) | free, local | offline | standalone binary + `.onnx` voice |
  | **OpenAI** | paid | cloud | `gpt-4o-mini-tts`, very natural |
  | **ElevenLabs** | paid | cloud | `eleven_multilingual_v2`, top fidelity |
  | **Kokoro** | free, local | offline | ONNX model, auto-downloaded; verified on macOS |
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
- Kokoro ONNX inference is wired to its interface but needs the native
  onnxruntime + model download verified on real hardware.
- Linux/Windows installer paths need verification on those platforms.
- Mobile/web targets; cloud cost estimation in the UI.
