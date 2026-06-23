# EPUB → M4B audiobook (French, high fidelity)

`epub_to_m4b.py` turns a DRM-free `.epub` into a chaptered `.m4b` audiobook:
chapters, title/author tags, and cover art are all embedded so it shows up
properly in Apple Books, VLC, Bookplayer, Smart AudioBook Player, etc.

The TTS step is **pluggable** — pick free/local or paid/cloud depending on the
quality you want.

---

## Quick start (free, local, good French)

```bash
# system deps
sudo apt install ffmpeg espeak-ng          # macOS: brew install ffmpeg espeak-ng
# python deps
pip install EbookLib beautifulsoup4 lxml soundfile numpy tqdm
pip install "kokoro>=0.9" "misaki[fr]"     # the local TTS model

python epub_to_m4b.py livre.epub --backend kokoro --voice ff_siwis
# -> "Titre du livre.m4b"
```

`ff_siwis` is Kokoro's French voice. On a CPU expect roughly **1 hour of
processing per ~600k characters** (a typical novel); a CUDA GPU is ~10× faster.
The run is **resumable** — finished chapters are cached in a `.work/` folder, so
if it stops you just rerun the same command.

### macOS setup (verified)

These are the exact steps that work on Apple Silicon macOS:

```bash
# system deps
brew install ffmpeg espeak-ng
# python deps (core + Kokoro local TTS with the French frontend)
pip install EbookLib beautifulsoup4 lxml soundfile numpy tqdm "kokoro>=0.9" "misaki[fr]"

# always sanity-check one chapter first (downloads the Kokoro model on first run)
python epub_to_m4b.py book.epub --backend kokoro --voice ff_siwis --limit 1 -o test.m4b

# then the full book; --cover embeds your own cover image
python epub_to_m4b.py book.epub --backend kokoro --voice ff_siwis --cover book.jpg
```

PyTorch is pulled in automatically as a Kokoro dependency. The model weights
download once from the Hugging Face Hub on the first synthesis. The first chunk
is slow (model warm-up); throughput steadies after that.

---

## Choosing a backend

| Backend | Cost | Quality (French) | Needs | Best for |
|---|---|---|---|---|
| `kokoro` | free, local | very good | espeak-ng, `misaki[fr]` | the default; private, no API key |
| `piper` | free, local | good, fast | `piper` binary + `fr_FR-*.onnx` voice | low-end hardware / batch |
| `openai` | ~$ | excellent, natural | `OPENAI_API_KEY` | easiest high quality |
| `elevenlabs` | $$$ | best-in-class | `ELEVENLABS_API_KEY` + `voice_id` | maximum fidelity |

```bash
# OpenAI (natural, cheap-ish, French narration instructions are sent automatically)
export OPENAI_API_KEY=sk-...
python epub_to_m4b.py livre.epub --backend openai --voice alloy

# ElevenLabs (highest fidelity; multilingual v2 handles French very well)
export ELEVENLABS_API_KEY=...
python epub_to_m4b.py livre.epub --backend elevenlabs --voice <voice_id>

# Piper (download a French voice first, e.g. fr_FR-siwis-medium or fr_FR-upmc-medium)
python epub_to_m4b.py livre.epub --backend piper --model ./fr_FR-siwis-medium.onnx
```

**Rough cloud cost for a 500k-character novel** (verify current pricing):
OpenAI `gpt-4o-mini-tts` is the cheap end, ElevenLabs the expensive end. Cloud
TTS bills per character, so a long book can cost from a few dollars to a few
tens of dollars. Local backends are free but slower and tie up your machine.

For **truly high fidelity French**, the ranked picks are roughly:
ElevenLabs `eleven_multilingual_v2` ≈ best, then OpenAI / Azure HD neural French
voices (`fr-FR-VivienneMultilingualNeural`, `fr-FR-RemyMultilingualNeural`),
then Kokoro/Piper locally. If you want voice cloning locally, look at XTTS-v2 or
Chatterbox Multilingual (both support French) — easy to add as another backend
class.

---

## Useful flags

```
--bitrate 192k     # AAC bitrate (96k/128k/192k). 128k mono is plenty for speech
--speed 1.1        # narration speed (0.5–2.0)
--limit 2          # only convert the first 2 chapters (great for a quick test)
--cover book.jpg   # embed this image as the cover (overrides the EPUB's own)
-o out.m4b         # explicit output path
--workdir cache/   # where chapter audio is cached for resume
```

Always test with `--limit 1` first to confirm the voice/quality before
committing to a multi-hour full-book run.

---

## Don't want to write/run anything? Turnkey alternative

[`audiblez`](https://github.com/santinic/audiblez) does essentially this
pipeline (Kokoro under the hood, French supported) with a one-line install and
even a GUI:

```bash
pip install audiblez
audiblez livre.epub -l fr-fr -v ff_siwis
```

Use it for zero-effort; use the script here when you want control over chunking,
chapter handling, bitrate, or to swap in a cloud/cloned voice.

---

## Note on doing this "fully online" in the chat

A full audiobook can't be generated inside the chat sandbox: it has no access to
TTS model weights or cloud TTS APIs, runs CPU-only with time/memory limits, and
the output (hours of audio, hundreds of MB) is too large to produce there. The
EPUB-parsing and M4B-assembly stages **were** tested in that sandbox and work;
only the TTS synthesis has to run on your own machine or via your API key. This
script is the result.
