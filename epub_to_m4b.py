#!/usr/bin/env python3
"""
epub_to_m4b.py — Convert an EPUB (e.g. French) into a high-fidelity chaptered .m4b audiobook.

Pipeline:
  EPUB  ->  parse chapters + metadata + cover  ->  clean & chunk text
        ->  TTS (pluggable backend)             ->  per-chapter WAV
        ->  ffmpeg assemble (AAC + chapter markers + cover + tags)  ->  book.m4b

Backends (pick with --backend):
  kokoro      Local, free, good quality, French voice 'ff_siwis'   (default)
  openai      Cloud, very natural, needs OPENAI_API_KEY
  elevenlabs  Cloud, highest fidelity, needs ELEVENLABS_API_KEY
  piper       Local, fast/light, needs the `piper` binary + a French .onnx voice

Requirements:
  pip install EbookLib beautifulsoup4 lxml soundfile numpy tqdm
  System: ffmpeg, and (for kokoro/piper) espeak-ng
  Backend extras:
    kokoro:     pip install "kokoro>=0.9" "misaki[fr]"
    openai:     pip install openai
    elevenlabs: pip install elevenlabs

Examples:
  python epub_to_m4b.py livre.epub --backend kokoro --voice ff_siwis
  python epub_to_m4b.py livre.epub --backend openai --voice alloy
  python epub_to_m4b.py livre.epub --backend elevenlabs --voice <voice_id>
"""

import argparse
import html
import os
import re
import shutil
import subprocess
import sys
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

# ----------------------------- EPUB parsing -----------------------------

import warnings
from ebooklib import epub, ITEM_DOCUMENT
from bs4 import BeautifulSoup, XMLParsedAsHTMLWarning

warnings.filterwarnings("ignore", category=XMLParsedAsHTMLWarning)


@dataclass
class Chapter:
    title: str
    text: str


@dataclass
class Book:
    title: str
    author: str
    language: str
    cover_path: str | None
    chapters: list[Chapter] = field(default_factory=list)


def _meta(book, name, default=""):
    try:
        vals = book.get_metadata("DC", name)
        return vals[0][0] if vals else default
    except Exception:
        return default


def _clean_text(raw_html: str) -> str:
    """Strip HTML to readable prose suitable for narration."""
    soup = BeautifulSoup(raw_html, "xml")
    # Drop elements we never want spoken
    for tag in soup(["script", "style", "sup", "sub", "nav", "table", "figure"]):
        tag.decompose()
    text = soup.get_text(" ")
    text = html.unescape(text)
    text = unicodedata.normalize("NFC", text)
    # collapse whitespace, keep paragraph breaks as a single space
    text = re.sub(r"\s+", " ", text).strip()
    return text


def _extract_cover(book, workdir: Path) -> str | None:
    # Try the proper cover metadata first, then fall back to any image named "cover".
    candidates = []
    for item in book.get_items():
        name = (item.get_name() or "").lower()
        media = (getattr(item, "media_type", "") or "")
        if media.startswith("image/"):
            score = 2 if "cover" in name else 0
            candidates.append((score, item))
    if not candidates:
        return None
    candidates.sort(key=lambda x: x[0], reverse=True)
    item = candidates[0][1]
    ext = ".jpg" if "jpeg" in (item.media_type or "") or item.get_name().lower().endswith((".jpg", ".jpeg")) else ".png"
    out = workdir / f"cover{ext}"
    out.write_bytes(item.get_content())
    return str(out)


def parse_epub(path: str, workdir: Path) -> Book:
    src = epub.read_epub(path)
    title = _meta(src, "title", Path(path).stem) or Path(path).stem
    author = _meta(src, "creator", "Inconnu") or "Inconnu"
    language = _meta(src, "language", "fr") or "fr"
    cover = _extract_cover(src, workdir)

    chapters: list[Chapter] = []
    # Walk the spine = real reading order; skip the navigation document and empty pages.
    for spine_id, _ in src.spine:
        item = src.get_item_with_id(spine_id)
        if item is None or item.get_type() != ITEM_DOCUMENT:
            continue
        name = (item.get_name() or "").lower()
        if "nav" in name or "toc" in name or "cover" in name:
            continue
        soup = BeautifulSoup(item.get_content(), "xml")
        heading = soup.find(["h1", "h2", "h3"])
        ch_title = heading.get_text(strip=True) if heading else None
        text = _clean_text(item.get_content())
        if len(text) < 20:  # skip title pages, dedications, blank sections (tune if needed)
            continue
        chapters.append(Chapter(ch_title or f"Chapitre {len(chapters) + 1}", text))

    if not chapters:
        raise SystemExit("No readable chapters found. Is the EPUB DRM-free and valid?")
    return Book(title, author, language, cover, chapters)


# ----------------------------- Text chunking -----------------------------

# Sentence-aware splitter tuned for French (handles « » and common punctuation).
_SENT_RE = re.compile(r"(?<=[.!?…»])\s+(?=[«“\"A-ZÀ-ÖØ-Þ0-9])")


def split_sentences(text: str) -> list[str]:
    parts = _SENT_RE.split(text)
    return [p.strip() for p in parts if p.strip()]


def chunk_text(text: str, max_chars: int) -> list[str]:
    """Group sentences into chunks under max_chars so TTS stays stable & in-limit."""
    chunks, cur = [], ""
    for sent in split_sentences(text):
        if len(sent) > max_chars:  # very long sentence: hard-split on spaces
            for i in range(0, len(sent), max_chars):
                chunks.append(sent[i:i + max_chars])
            continue
        if len(cur) + len(sent) + 1 <= max_chars:
            cur = f"{cur} {sent}".strip()
        else:
            if cur:
                chunks.append(cur)
            cur = sent
    if cur:
        chunks.append(cur)
    return chunks


# ----------------------------- TTS backends -----------------------------

class TTSBackend:
    """A backend turns a piece of text into a mono WAV file at self.sample_rate."""
    sample_rate = 24000
    max_chars = 1500

    def synth(self, text: str, out_wav: str) -> None:
        raise NotImplementedError


class KokoroBackend(TTSBackend):
    """Local, free. French: lang_code='f', voice 'ff_siwis'. Needs espeak-ng + misaki[fr]."""
    sample_rate = 24000
    max_chars = 1800

    def __init__(self, voice="ff_siwis", lang_code="f", speed=1.0):
        from kokoro import KPipeline  # imported lazily
        import soundfile  # noqa: F401
        self.voice, self.speed = voice, speed
        self.pipeline = KPipeline(lang_code=lang_code)

    def synth(self, text, out_wav):
        import numpy as np
        import soundfile as sf
        audio_parts = []
        for _, _, audio in self.pipeline(text, voice=self.voice, speed=self.speed):
            audio_parts.append(audio)
        if not audio_parts:
            audio = np.zeros(int(0.2 * self.sample_rate), dtype="float32")
        else:
            audio = np.concatenate(audio_parts)
        sf.write(out_wav, audio, self.sample_rate)


class OpenAIBackend(TTSBackend):
    """Cloud. gpt-4o-mini-tts is natural and cheap; pass French narration instructions."""
    sample_rate = 24000
    max_chars = 3500

    def __init__(self, voice="alloy", model="gpt-4o-mini-tts", speed=1.0):
        from openai import OpenAI
        self.client = OpenAI()  # reads OPENAI_API_KEY
        self.voice, self.model, self.speed = voice, model, speed
        self.instructions = (
            "Lis ce texte en français avec une diction claire, naturelle et posée, "
            "sur un ton de narration de livre audio."
        )

    def synth(self, text, out_wav):
        kwargs = dict(model=self.model, voice=self.voice, input=text, response_format="wav")
        if self.model == "gpt-4o-mini-tts":
            kwargs["instructions"] = self.instructions
        with self.client.audio.speech.with_streaming_response.create(**kwargs) as resp:
            resp.stream_to_file(out_wav)


class ElevenLabsBackend(TTSBackend):
    """Cloud, highest fidelity. eleven_multilingual_v2 handles French very well."""
    sample_rate = 44100
    max_chars = 2500

    def __init__(self, voice="EXAVITQu4vr4xnSDxMaL", model="eleven_multilingual_v2", speed=1.0):
        from elevenlabs.client import ElevenLabs
        self.client = ElevenLabs()  # reads ELEVENLABS_API_KEY
        self.voice_id, self.model = voice, model

    def synth(self, text, out_wav):
        # Request PCM and wrap as WAV so all backends share one path.
        import io, wave
        audio = self.client.text_to_speech.convert(
            voice_id=self.voice_id, model_id=self.model, text=text,
            output_format="pcm_44100",
        )
        pcm = b"".join(audio) if hasattr(audio, "__iter__") else audio
        with wave.open(out_wav, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(44100)
            w.writeframes(pcm)


class PiperBackend(TTSBackend):
    """Local, fast. Needs the `piper` binary and a French voice model (.onnx + .onnx.json)."""
    sample_rate = 22050
    max_chars = 2000

    def __init__(self, model_path, piper_bin="piper", speed=1.0):
        self.model_path = model_path
        self.piper_bin = piper_bin
        self.length_scale = 1.0 / max(0.1, speed)

    def synth(self, text, out_wav):
        subprocess.run(
            [self.piper_bin, "--model", self.model_path,
             "--length_scale", str(self.length_scale), "--output_file", out_wav],
            input=text.encode("utf-8"), check=True, capture_output=True,
        )


def make_backend(args) -> TTSBackend:
    if args.backend == "kokoro":
        return KokoroBackend(voice=args.voice or "ff_siwis", speed=args.speed)
    if args.backend == "openai":
        return OpenAIBackend(voice=args.voice or "alloy", model=args.model or "gpt-4o-mini-tts", speed=args.speed)
    if args.backend == "elevenlabs":
        if not args.voice:
            raise SystemExit("--voice <voice_id> is required for elevenlabs")
        return ElevenLabsBackend(voice=args.voice, model=args.model or "eleven_multilingual_v2", speed=args.speed)
    if args.backend == "piper":
        if not args.model:
            raise SystemExit("--model /path/to/fr_FR-xxx.onnx is required for piper")
        return PiperBackend(model_path=args.model, speed=args.speed)
    raise SystemExit(f"Unknown backend: {args.backend}")


# ----------------------------- ffmpeg helpers -----------------------------

def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-2000:] + "\n")
        raise SystemExit(f"ffmpeg failed: {' '.join(cmd[:6])} ...")
    return r


def concat_to_chapter_wav(chunk_wavs, out_wav, sample_rate):
    """Merge chunk WAVs into one normalized mono chapter WAV via the concat filter."""
    if len(chunk_wavs) == 1:
        run(["ffmpeg", "-y", "-i", chunk_wavs[0], "-ar", str(sample_rate), "-ac", "1", out_wav])
        return
    inputs = []
    for w in chunk_wavs:
        inputs += ["-i", w]
    n = len(chunk_wavs)
    streams = "".join(f"[{i}:a]" for i in range(n))
    filt = f"{streams}concat=n={n}:v=0:a=1[a]"
    run(["ffmpeg", "-y", *inputs, "-filter_complex", filt,
         "-map", "[a]", "-ar", str(sample_rate), "-ac", "1", out_wav])


def wav_duration_ms(path) -> int:
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", path],
        capture_output=True, text=True, check=True)
    return int(float(r.stdout.strip()) * 1000)


def build_ffmetadata(book: Book, chapter_files, path):
    def esc(s):  # escape ffmetadata special chars
        return re.sub(r"([=;#\\\n])", r"\\\1", s)

    lines = [";FFMETADATA1",
             f"title={esc(book.title)}",
             f"artist={esc(book.author)}",
             f"album_artist={esc(book.author)}",
             f"album={esc(book.title)}",
             "genre=Audiobook",
             f"language={esc(book.language)}"]
    start = 0
    for ch, wav in zip(book.chapters, chapter_files):
        dur = wav_duration_ms(wav)
        end = start + dur
        lines += ["[CHAPTER]", "TIMEBASE=1/1000",
                  f"START={start}", f"END={end}", f"title={esc(ch.title)}"]
        start = end
    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")


def assemble_m4b(book: Book, chapter_files, workdir: Path, out_path, bitrate, sample_rate):
    # 1) concat list (all chapter wavs share identical format -> demuxer copy is safe)
    list_file = workdir / "concat.txt"
    list_file.write_text("".join(f"file '{Path(w).resolve()}'\n" for w in chapter_files),
                         encoding="utf-8")
    # 2) chapter + tag metadata
    meta_file = workdir / "ffmeta.txt"
    build_ffmetadata(book, chapter_files, meta_file)

    cmd = ["ffmpeg", "-y",
           "-f", "concat", "-safe", "0", "-i", str(list_file),
           "-i", str(meta_file)]
    if book.cover_path:
        cmd += ["-i", book.cover_path]

    cmd += ["-map", "0:a"]
    if book.cover_path:
        cmd += ["-map", "2:v"]
    cmd += ["-map_metadata", "1", "-map_chapters", "1",
            "-c:a", "aac", "-b:a", bitrate, "-ar", str(sample_rate), "-ac", "1"]
    if book.cover_path:
        cmd += ["-c:v", "mjpeg", "-disposition:v", "attached_pic"]
    cmd += ["-movflags", "+faststart", str(out_path)]
    run(cmd)


# ----------------------------- Orchestration -----------------------------

def main():
    ap = argparse.ArgumentParser(description="Convert an EPUB to a chaptered .m4b audiobook.")
    ap.add_argument("epub", help="Path to the .epub file (DRM-free)")
    ap.add_argument("-o", "--output", help="Output .m4b path (default: <book title>.m4b)")
    ap.add_argument("--backend", default="kokoro",
                    choices=["kokoro", "openai", "elevenlabs", "piper"])
    ap.add_argument("--voice", help="Voice name/id (backend-specific)")
    ap.add_argument("--model", help="Model name or voice .onnx path (backend-specific)")
    ap.add_argument("--speed", type=float, default=1.0, help="Speech rate (0.5–2.0)")
    ap.add_argument("--cover", help="Cover image to embed (overrides the EPUB's own cover)")
    ap.add_argument("--bitrate", default="128k", help="AAC bitrate, e.g. 96k/128k/192k")
    ap.add_argument("--workdir", default=None, help="Cache dir (default: <output>.work)")
    ap.add_argument("--limit", type=int, default=0, help="Only process first N chapters (testing)")
    args = ap.parse_args()

    if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        raise SystemExit("ffmpeg/ffprobe not found. Install ffmpeg first.")

    out_path = Path(args.output) if args.output else None
    workdir = Path(args.workdir) if args.workdir else Path((args.output or args.epub) + ".work")
    workdir.mkdir(parents=True, exist_ok=True)

    print(f"Parsing {args.epub} ...")
    book = parse_epub(args.epub, workdir)
    if args.cover:
        if not Path(args.cover).is_file():
            raise SystemExit(f"--cover file not found: {args.cover}")
        book.cover_path = args.cover
    if args.limit:
        book.chapters = book.chapters[:args.limit]
    if out_path is None:
        safe = re.sub(r"[^\w\- ]+", "", book.title).strip() or "audiobook"
        out_path = Path(f"{safe}.m4b")
    print(f"  Title : {book.title}\n  Author: {book.author}\n  Chapters: {len(book.chapters)}"
          f"\n  Cover : {'yes' if book.cover_path else 'no'}")

    print(f"Loading TTS backend: {args.backend} ...")
    tts = make_backend(args)

    try:
        from tqdm import tqdm
    except ImportError:
        def tqdm(x, **k):  # graceful fallback
            return x

    chapter_files = []
    for ci, ch in enumerate(book.chapters):
        ch_wav = workdir / f"chapter_{ci:04d}.wav"
        if ch_wav.exists():  # resume support
            print(f"[{ci+1}/{len(book.chapters)}] cached: {ch.title}")
            chapter_files.append(str(ch_wav))
            continue

        chunks = chunk_text(ch.text, tts.max_chars)
        chunk_wavs = []
        print(f"[{ci+1}/{len(book.chapters)}] {ch.title}  ({len(ch.text)} chars, {len(chunks)} chunks)")
        for ki, chunk in enumerate(tqdm(chunks, desc="  synth", leave=False)):
            cw = workdir / f"chapter_{ci:04d}_chunk_{ki:04d}.wav"
            if not cw.exists():
                tts.synth(chunk, str(cw))
            chunk_wavs.append(str(cw))

        concat_to_chapter_wav(chunk_wavs, str(ch_wav), tts.sample_rate)
        for cw in chunk_wavs:  # free disk once merged
            try:
                os.remove(cw)
            except OSError:
                pass
        chapter_files.append(str(ch_wav))

    print(f"Assembling {out_path} ...")
    assemble_m4b(book, chapter_files, workdir, out_path, args.bitrate, tts.sample_rate)
    print(f"Done -> {out_path}")
    print("(You can delete the .work cache directory once you're happy with the result.)")


if __name__ == "__main__":
    main()
