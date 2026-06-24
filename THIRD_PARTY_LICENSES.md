# Licensing & third-party components

This project is licensed under the **GNU General Public License v3.0** (see
[`LICENSE`](LICENSE)).

## Compatibility summary

Every component compiled into or shipped with this software uses a
GPL-3.0-compatible license. GPLv3 is a strong-copyleft license; permissive
licenses (MIT/BSD/ISC/Apache-2.0) may be combined into a GPLv3 work, and
GPL-licensed components require the combined work to be GPLv3 — which it is.

| Component | Role | License | Compatible with GPL-3.0 |
|---|---|---|---|
| Flutter / Dart SDK | framework | BSD-3-Clause | ✅ |
| sherpa_onnx (Dart pkg) | local TTS runtime | Apache-2.0 | ✅ (Apache-2.0 → GPLv3) |
| onnxruntime (bundled by sherpa) | inference | MIT | ✅ |
| espeak-ng (bundled by sherpa) | phonemizer | **GPL-3.0** | ✅ (same license) |
| http | networking | BSD-3-Clause | ✅ |
| archive | zip/tar/bzip2 | MIT | ✅ |
| xml, html | EPUB parsing | MIT / ISC | ✅ |
| file_picker | file dialogs | MIT | ✅ |
| path, path_provider, crypto, args | utilities | BSD-3-Clause | ✅ |
| google_fonts + Fraunces/Hanken Grotesk | UI fonts | BSD-3 / SIL OFL | ✅ |

`espeak-ng` being GPL-3.0 is the strongest constraint in the local TTS stack and
is precisely why GPL-3.0 is the appropriate license here.

## External tools (not linked)

- **ffmpeg / ffprobe** are invoked as separate processes (not linked into the
  app), so this is mere aggregation — no license propagation. Users install
  ffmpeg themselves (its own LGPL/GPL terms apply to that binary).

## Runtime-downloaded models (user's responsibility)

TTS model weights are **downloaded by the user at runtime** and are **not
distributed with this source**, so they don't affect this project's license.
Their own licenses still apply to the downloaded files:

- **Piper / VITS voices** — typically MIT / CC0 / CC-BY (per voice).
- **Kokoro** — Apache-2.0.
- **Matcha / Kitten** — see their model cards.
- **MMS (Meta)** — **CC-BY-NC 4.0 (non-commercial)**. Do not use MMS voices in a
  commercial audiobook without checking Meta's terms; prefer Piper/Kokoro for
  commercial use.
