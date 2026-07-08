# Reel-Summarize Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `reel-summarize` CLI tool that downloads an Instagram Reel and returns a concise prose summary combining audio transcription, OCR'd overlay text, visual descriptions, and post caption — all local via Ollama vision models and faster-whisper.

**Architecture:** Python package in ~/.config/nix/pkgs/reel-summarize/ (mirroring what-changed). Pipeline: yt-dlp download → ffmpeg frames+audio → faster-whisper transcription → qwen2-vl per-frame OCR → qwen2.5 summary. Nix-managed (faster-whisper available in nixpkgs). Opencode skill at ~/.config/opencode/skills/reel-summarize/SKILL.md.

**Tech Stack:** Python 3, httpx (ollama API), faster-whisper (transcription), subprocess (yt-dlp, ffmpeg), nix (packaging), opencode skills.

## Global Constraints

- All processing is local (Ollama), zero cloud API keys
- `faster-whisper` is available in nixpkgs as `python3Packages.faster-whisper` — tool imports it as a Python library
- yt-dlp + ffmpeg are already system-installed via nix
- faster-whisper is available in nixpkgs as `python3Packages.faster-whisper` — tool imports it as a Python library
- Python 3.10+ (same floor as what-changed)
- Cross-platform (faster-whisper has no platform restriction), but only enabled on accismus for v1
- Replicate what-changed conventions: ruff for lint, alejandra for nix, pytest for tests
- Output: concise prose summary to stdout (5-10 sentences), progress to stderr

---

### Task 1: Python package skeleton, config, and test infrastructure

**Files:**
- Create: `~/.config/nix/pkgs/reel-summarize/.gitignore`
- Create: `~/.config/nix/pkgs/reel-summarize/pyproject.toml`
- Create: `~/.config/nix/pkgs/reel-summarize/reel_summarize/__init__.py`
- Create: `~/.config/nix/pkgs/reel-summarize/reel_summarize/__main__.py`
- Create: `~/.config/nix/pkgs/reel-summarize/reel_summarize/config.py`
- Create: `~/.config/nix/pkgs/reel-summarize/tests/__init__.py`
- Create: `~/.config/nix/pkgs/reel-summarize/tests/test_config.py`

**Interfaces:**
- Consumes: nothing (first task)
- Produces: `reel_summarize.config.Config` dataclass, `reel_summarize.config.load()` function, pyproject.toml exposing `reel-summarize = "reel_summarize.cli:entry"`

- [ ] **Step 1: Create .gitignore**

```
__pycache__/
*.pyc
```

- [ ] **Step 2: Create pyproject.toml**

```toml
[build-system]
requires = ["setuptools"]
build-backend = "setuptools.build_meta"

[project]
name = "reel-summarize"
version = "0.1.0"
description = "Summarize Instagram Reels using local models"
requires-python = ">=3.10"
dependencies = ["httpx", "faster-whisper"]

[project.scripts]
reel-summarize = "reel_summarize.cli:entry"

[tool.setuptools.packages.find]
include = ["reel_summarize*"]
```

- [ ] **Step 3: Create reel_summarize/__init__.py** (empty file)

- [ ] **Step 4: Create reel_summarize/__main__.py**

```python
from reel_summarize.cli import entry

if __name__ == "__main__":
    entry()
```

- [ ] **Step 5: Create reel_summarize/config.py**

```python
from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, fields

CONFIG_PATH = os.path.expanduser("~/.config/reel-summarize/config.toml")


@dataclass
class Config:
    host: str = "http://localhost:11434"
    vision_model: str = "qwen2-vl:7b"
    summarize_model: str = "qwen2.5:7b"
    whisper_model: str = "small"
    frames_per_second: int = 1
    max_frames: int = 60
    timeout: int = 180


def load(path: str | None = None) -> Config:
    cfg = Config()
    p = path or CONFIG_PATH
    if os.path.exists(p):
        with open(p, "rb") as f:
            raw = tomllib.load(f)
        for fld in fields(cfg):
            if fld.name in raw:
                setattr(cfg, fld.name, raw[fld.name])
    # env overrides
    env = {
        "host": "REEL_SUMMARIZE_OLLAMA_HOST",
        "vision_model": "REEL_SUMMARIZE_VISION_MODEL",
        "summarize_model": "REEL_SUMMARIZE_MODEL",
        "whisper_model": "REEL_SUMMARIZE_WHISPER_MODEL",
    }
    for attr, var in env.items():
        val = os.environ.get(var)
        if val is not None:
            setattr(cfg, attr, val)
    return cfg
```

- [ ] **Step 6: Create tests/__init__.py** (empty file)

- [ ] **Step 7: Create tests/test_config.py**

```python
import os
import tempfile
import unittest
from reel_summarize.config import Config, load


class TestConfig(unittest.TestCase):
    def test_defaults(self):
        cfg = load("/nonexistent/path")
        self.assertEqual(cfg.host, "http://localhost:11434")
        self.assertEqual(cfg.vision_model, "qwen2-vl:7b")
        self.assertEqual(cfg.frames_per_second, 1)

    def test_toml_overrides(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".toml", delete=False) as f:
            f.write('frames_per_second = 2\n')
            f.write('max_frames = 10\n')
            path = f.name
        try:
            cfg = load(path)
            self.assertEqual(cfg.frames_per_second, 2)
            self.assertEqual(cfg.max_frames, 10)
        finally:
            os.unlink(path)

    def test_env_overrides(self):
        os.environ["REEL_SUMMARIZE_OLLAMA_HOST"] = "http://other:11434"
        try:
            cfg = load("/nonexistent/path")
            self.assertEqual(cfg.host, "http://other:11434")
        finally:
            del os.environ["REEL_SUMMARIZE_OLLAMA_HOST"]
```

- [ ] **Step 8: Verify tests pass**

Run: `python -m pytest ~/.config/nix/pkgs/reel-summarize/tests/test_config.py -v`
Expected: 3 passed

- [ ] **Step 9: Commit**

```bash
git add .config/nix/pkgs/reel-summarize/
git commit -m "reel-summarize: add python package skeleton, config, test infra"
```

---

### Task 2: Download, audio, and frame extraction stages

**Files:**
- Create: `~/.config/nix/pkgs/reel-summarize/reel_summarize/stages/__init__.py`
- Create: `~/.config/nix/pkgs/reel-summarize/reel_summarize/stages/download.py`
- Create: `~/.config/nix/pkgs/reel-summarize/reel_summarize/stages/audio_extract.py`
- Create: `~/.config/nix/pkgs/reel-summarize/reel_summarize/stages/frame_extract.py`
- Create: `~/.config/nix/pkgs/reel-summarize/tests/test_stages.py`

**Interfaces:**
- Consumes: `reel_summarize.config.Config`
- Produces:
  - `download(url: str, work_dir: str) -> dict` — returns `{"video_path": str, "metadata": {"caption": str|None, "author": str|None, "duration": int|None}}`
  - `extract_audio(video_path: str, work_dir: str) -> str` — returns path to `audio.wav`
  - `extract_frames(video_path: str, work_dir: str, cfg: Config) -> list[str]` — returns sorted list of frame jpg paths

- [ ] **Step 1: Create stages/__init__.py** (empty file)

- [ ] **Step 2: Create download.py**

Uses yt-dlp to download the video and extract metadata.

```python
from __future__ import annotations

import json
import os
import subprocess
import sys


def download(url: str, work_dir: str) -> dict:
    video_path = os.path.join(work_dir, "reel.mp4")
    meta_path = os.path.join(work_dir, "metadata.json")

    # Download video
    result = subprocess.run(
        ["yt-dlp", "-o", video_path, "--print", "after_move:%(filename)s", url],
        capture_output=True, text=True, timeout=300,
    )
    if result.returncode != 0:
        print(f"  yt-dlp error: {result.stderr.strip() or result.stdout.strip()}", file=sys.stderr)
        sys.exit(3)

    # Fetch metadata
    meta_result = subprocess.run(
        ["yt-dlp", "--dump-json", url],
        capture_output=True, text=True, timeout=30,
    )
    metadata = {"caption": None, "author": None, "duration": None}
    if meta_result.returncode == 0 and meta_result.stdout:
        try:
            data = json.loads(meta_result.stdout)
            metadata["caption"] = data.get("description") or data.get("title")
            metadata["author"] = data.get("uploader") or data.get("channel")
            metadata["duration"] = data.get("duration")
        except json.JSONDecodeError:
            pass

    # Write metadata
    with open(meta_path, "w") as f:
        json.dump(metadata, f)

    return {"video_path": video_path, "metadata": metadata}
```

- [ ] **Step 3: Create audio_extract.py**

```python
from __future__ import annotations

import os
import subprocess
import sys


def extract_audio(video_path: str, work_dir: str) -> str:
    audio_path = os.path.join(work_dir, "audio.wav")
    result = subprocess.run(
        ["ffmpeg", "-y", "-i", video_path,
         "-ar", "16000", "-ac", "1", audio_path],
        capture_output=True, text=True, timeout=120,
    )
    if result.returncode != 0:
        print(f"  ffmpeg error: {result.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    return audio_path
```

- [ ] **Step 4: Create frame_extract.py**

```python
from __future__ import annotations

import glob
import os
import subprocess
import sys

from reel_summarize.config import Config


def extract_frames(video_path: str, work_dir: str, cfg: Config) -> list[str]:
    frames_dir = os.path.join(work_dir, "frames")
    os.makedirs(frames_dir, exist_ok=True)
    pattern = os.path.join(frames_dir, "frame_%04d.jpg")
    result = subprocess.run(
        ["ffmpeg", "-y", "-i", video_path,
         "-vf", f"fps={cfg.frames_per_second}",
         "-frames:v", str(cfg.max_frames),
         pattern],
        capture_output=True, text=True, timeout=120,
    )
    if result.returncode != 0:
        print(f"  ffmpeg error: {result.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    frames = sorted(glob.glob(os.path.join(frames_dir, "frame_*.jpg")))
    if not frames:
        print("  warning: no frames extracted, continuing without vision", file=sys.stderr)
    return frames
```

- [ ] **Step 5: Create tests/test_stages.py**

```python
import json
import os
import tempfile
import unittest
from unittest.mock import patch, MagicMock
from reel_summarize.config import Config
from reel_summarize.stages.download import download
from reel_summarize.stages.audio_extract import extract_audio
from reel_summarize.stages.frame_extract import extract_frames


class TestDownload(unittest.TestCase):
    @patch("reel_summarize.stages.download.subprocess.run")
    def test_download_success(self, mock_run):
        mock_run.return_value.returncode = 0
        mock_run.return_value.stdout = json.dumps({
            "description": "cool reel",
            "uploader": "user",
            "duration": 30,
        })
        with tempfile.TemporaryDirectory() as tmp:
            result = download("https://instagram.com/reel/xyz", tmp)
            self.assertIn("video_path", result)
            self.assertEqual(result["metadata"]["caption"], "cool reel")

    @patch("reel_summarize.stages.download.subprocess.run")
    def test_download_failure(self, mock_run):
        mock_run.return_value.returncode = 1
        mock_run.return_value.stderr = "HTTP Error 404"
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(SystemExit):
                download("https://instagram.com/reel/bad", tmp)


class TestAudioExtract(unittest.TestCase):
    @patch("reel_summarize.stages.audio_extract.subprocess.run")
    def test_extract(self, mock_run):
        mock_run.return_value.returncode = 0
        with tempfile.TemporaryDirectory() as tmp:
            video = os.path.join(tmp, "reel.mp4")
            open(video, "w").close()
            result = extract_audio(video, tmp)
            self.assertEqual(result, os.path.join(tmp, "audio.wav"))


class TestFrameExtract(unittest.TestCase):
    @patch("reel_summarize.stages.frame_extract.subprocess.run")
    @patch("reel_summarize.stages.frame_extract.glob.glob")
    def test_extract_frames(self, mock_glob, mock_run):
        mock_run.return_value.returncode = 0
        mock_glob.return_value = ["frame_0001.jpg", "frame_0002.jpg"]
        cfg = Config()
        with tempfile.TemporaryDirectory() as tmp:
            video = os.path.join(tmp, "reel.mp4")
            open(video, "w").close()
            frames = extract_frames(video, tmp, cfg)
            self.assertEqual(len(frames), 2)
```

- [ ] **Step 6: Verify tests pass**

Run: `python -m pytest ~/.config/nix/pkgs/reel-summarize/tests/test_stages.py -v`
Expected: 3 passed

- [ ] **Step 7: Commit**

```bash
git add .config/nix/pkgs/reel-summarize/
git commit -m "reel-summarize: add download, audio, frame extraction stages"
```

---

### Task 3: Transcription stage (faster-whisper)

**Files:**
- Create: `~/.config/nix/pkgs/reel-summarize/reel_summarize/stages/transcribe.py`

**Interfaces:**
- Consumes: `Config` (for `whisper_model`)
- Produces: `transcribe(audio_path: str, cfg: Config) -> list[dict]` — list of `{"start": float, "end": float, "text": str}`

- [ ] **Step 1: Create transcribe.py**

Uses `faster_whisper.WhisperModel` as a Python library (importable because nix provides it in propagatedBuildInputs).

```python
from __future__ import annotations

from faster_whisper import WhisperModel

from reel_summarize.config import Config


def transcribe(audio_path: str, cfg: Config) -> list[dict]:
    model = WhisperModel(cfg.whisper_model, device="cpu", compute_type="int8")
    segments, _info = model.transcribe(audio_path)
    result = []
    for seg in segments:
        result.append({
            "start": seg.start,
            "end": seg.end,
            "text": seg.text.strip(),
        })
    return result


def transcribe_text(segments: list[dict]) -> str:
    return " ".join(s["text"] for s in segments if s["text"])
```

- [ ] **Step 2: Create tests/test_transcribe.py**

```python
import unittest
from unittest.mock import patch, MagicMock
from reel_summarize.config import Config
from reel_summarize.stages.transcribe import transcribe, transcribe_text


class TestTranscribe(unittest.TestCase):
    @patch("reel_summarize.stages.transcribe.WhisperModel")
    def test_transcribe(self, mock_model_cls):
        mock_model = MagicMock()
        mock_model_cls.return_value = mock_model

        seg = MagicMock()
        seg.start = 0.0
        seg.end = 1.5
        seg.text = "hello world"
        mock_model.transcribe.return_value = ([seg], None)

        cfg = Config()
        segments = transcribe("/tmp/audio.wav", cfg)
        self.assertEqual(len(segments), 1)
        self.assertEqual(segments[0]["text"], "hello world")

    def test_transcribe_text(self):
        segments = [
            {"start": 0.0, "end": 1.0, "text": "hello"},
            {"start": 1.0, "end": 2.0, "text": "world"},
        ]
        self.assertEqual(transcribe_text(segments), "hello world")
```

- [ ] **Step 3: Verify tests pass**

Run: `python -m pytest ~/.config/nix/pkgs/reel-summarize/tests/test_transcribe.py -v`
Expected: 2 passed

- [ ] **Step 4: Commit**

```bash
git add .config/nix/pkgs/reel-summarize/
git commit -m "reel-summarize: add faster-whisper transcription stage"
```

---

### Task 4: Vision stage (per-frame qwen2-vl via Ollama HTTP)

**Files:**
- Create: `~/.config/nix/pkgs/reel-summarize/reel_summarize/stages/vision.py`

**Interfaces:**
- Consumes: `Config` (for `host`, `vision_model`), list of frame paths
- Produces: `analyze_frames(frames: list[str], cfg: Config) -> list[dict]` — list of `{"frame": str, "text": list[str], "scene": str}`

- [ ] **Step 1: Create vision.py**

```python
from __future__ import annotations

import base64
import json
import sys

import httpx

from reel_summarize.config import Config


def _encode_image(path: str) -> str:
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


_VISION_PROMPT = (
    "Extract all visible on-screen text verbatim from this image, "
    "then describe the scene in one sentence. "
    'Output JSON with keys "text" (array of strings) and "scene" (string).'
)


def _call_ollama_vision(image_b64: str, cfg: Config) -> dict:
    payload = {
        "model": cfg.vision_model,
        "prompt": _VISION_PROMPT,
        "images": [image_b64],
        "stream": False,
    }
    try:
        resp = httpx.post(
            f"{cfg.host}/api/generate",
            json=payload,
            timeout=120,
        )
        resp.raise_for_status()
        text = resp.json().get("response", "")
        # Try to parse JSON from the response
        text = text.strip()
        if text.startswith("```"):
            text = text.split("\n", 1)[-1]
            text = text.rsplit("```", 1)[0]
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return {"text": [text], "scene": ""}
    except httpx.RequestError as e:
        print(f"  error: cannot reach Ollama at {cfg.host}: {e}", file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f"  vision error: {e}", file=sys.stderr)
        return {"text": [], "scene": ""}


def analyze_frames(frames: list[str], cfg: Config) -> list[dict]:
    results = []
    total = len(frames)
    for i, path in enumerate(frames):
        img_b64 = _encode_image(path)
        result = _call_ollama_vision(img_b64, cfg)
        results.append({
            "frame": path,
            "text": result.get("text", []),
            "scene": result.get("scene", ""),
        })
        print(f"  scanned frame {i+1}/{total}", file=sys.stderr)
    return results


def format_vision_timeline(frames: list[str], vision_results: list[dict], fps: int = 1) -> str:
    lines = []
    for i, vr in enumerate(vision_results):
        timestamp = i / fps
        text_lines = vr.get("text", [])
        scene = vr.get("scene", "")
        parts = []
        if text_lines:
            parts.append(f"text: {text_lines}")
        if scene:
            parts.append(f"scene: {scene}")
        if parts:
            lines.append(f"    [t={timestamp:.0f}s] {'; '.join(parts)}")
    return "\n".join(lines)
```

- [ ] **Step 2: Create tests/test_vision.py**

```python
import json
import tempfile
import unittest
from unittest.mock import patch, MagicMock
from reel_summarize.config import Config
from reel_summarize.stages.vision import analyze_frames, format_vision_timeline


class TestVision(unittest.TestCase):
    @patch("reel_summarize.stages.vision.httpx.post")
    def test_vision_call(self, mock_post):
        mock_response = MagicMock()
        mock_response.json.return_value = {"response": '{"text": ["Hello"], "scene": "a person talking"}'}
        mock_response.raise_for_status.return_value = None
        mock_post.return_value = mock_response

        cfg = Config()
        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as f:
            f.write(b"fake image data")
            f.flush()
            frames = [f.name]

        results = analyze_frames(frames, cfg)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["text"], ["Hello"])
        self.assertEqual(results[0]["scene"], "a person talking")

    def test_format_timeline(self):
        frames = ["f1.jpg", "f2.jpg"]
        results = [
            {"text": ["Hello"], "scene": "person talking"},
            {"text": ["Buy now"], "scene": "product shown"},
        ]
        timeline = format_vision_timeline(frames, results, fps=1)
        self.assertIn("[t=0s]", timeline)
        self.assertIn("Hello", timeline)
        self.assertIn("[t=1s]", timeline)
        self.assertIn("Buy now", timeline)

    def test_vision_fallback_on_bad_json(self):
        with patch("reel_summarize.stages.vision.httpx.post") as mock_post:
            mock_response = MagicMock()
            mock_response.json.return_value = {"response": "raw text output"}
            mock_response.raise_for_status.return_value = None
            mock_post.return_value = mock_response

            cfg = Config()
            with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as f:
                f.write(b"fake")
                f.flush()

            results = analyze_frames([f.name], cfg)
            self.assertIn("raw text output", results[0]["text"])
```

- [ ] **Step 3: Verify tests pass**

Run: `python -m pytest ~/.config/nix/pkgs/reel-summarize/tests/test_vision.py -v`
Expected: 3 passed

- [ ] **Step 4: Commit**

```bash
git add .config/nix/pkgs/reel-summarize/
git commit -m "reel-summarize: add vision stage (per-frame qwen2-vl via ollama)"
```

---

### Task 5: Summarize stage (qwen2.5 via Ollama)

**Files:**
- Create: `~/.config/nix/pkgs/reel-summarize/reel_summarize/stages/summarize.py`

**Interfaces:**
- Consumes: `Config`, transcript text, vision timeline, metadata
- Produces: `generate_summary(transcript: str, vision_timeline: str, caption: str|None, author: str|None, cfg: Config) -> str`

- [ ] **Step 1: Create summarize.py**

```python
from __future__ import annotations

import sys

import httpx

from reel_summarize.config import Config


_FINAL_PROMPT = (
    "You are summarizing an Instagram Reel.\n"
    "Inputs below:\n"
    "- Author: {author}\n"
    "- Original caption: {caption}\n"
    "- Spoken audio transcript: {transcript}\n"
    "- Per-frame on-screen text + scene descriptions:\n"
    "{vision_timeline}\n"
    "\n"
    "Write a concise prose summary (5-10 sentences) of what the reel is about. "
    "Include both what's said and what's shown on screen. "
    "Do not use headers or bullet points \u2014 just prose."
)


def generate_summary(
    transcript: str,
    vision_timeline: str,
    caption: str | None,
    author: str | None,
    cfg: Config,
) -> str:
    prompt = _FINAL_PROMPT.format(
        author=author or "unknown",
        caption=caption or "(no caption)",
        transcript=transcript or "(no spoken audio)",
        vision_timeline=vision_timeline or "(no frames analyzed)",
    )
    payload = {
        "model": cfg.summarize_model,
        "prompt": prompt,
        "stream": False,
        "options": {"num_predict": 512},
    }
    try:
        resp = httpx.post(
            f"{cfg.host}/api/generate",
            json=payload,
            timeout=cfg.timeout,
        )
        resp.raise_for_status()
        return resp.json().get("response", "").strip()
    except httpx.RequestError as e:
        print(f"  error: cannot reach Ollama at {cfg.host}: {e}", file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f"  error during summarization: {e}", file=sys.stderr)
        sys.exit(1)
```

- [ ] **Step 2: Create tests/test_summarize.py**

```python
import unittest
from unittest.mock import patch, MagicMock
from reel_summarize.config import Config
from reel_summarize.stages.summarize import generate_summary


class TestSummarize(unittest.TestCase):
    @patch("reel_summarize.stages.summarize.httpx.post")
    def test_generate_summary(self, mock_post):
        mock_response = MagicMock()
        mock_response.json.return_value = {"response": "This reel is about cats."}
        mock_response.raise_for_status.return_value = None
        mock_post.return_value = mock_response

        cfg = Config()
        result = generate_summary(
            transcript="cats are great",
            vision_timeline="[t=0s] scene: cat; text: ['meow']",
            caption="Cute cat video",
            author="catlover",
            cfg=cfg,
        )
        self.assertEqual(result, "This reel is about cats.")
        # Verify the prompt included the data
        call_args = mock_post.call_args
        self.assertIsNotNone(call_args)
        payload = call_args[1]["json"]
        self.assertIn("catlover", payload["prompt"])
        self.assertIn("Cute cat video", payload["prompt"])
        self.assertIn("cats are great", payload["prompt"])
```

- [ ] **Step 3: Verify tests pass**

Run: `python -m pytest ~/.config/nix/pkgs/reel-summarize/tests/test_summarize.py -v`
Expected: 1 passed

- [ ] **Step 4: Commit**

```bash
git add .config/nix/pkgs/reel-summarize/
git commit -m "reel-summarize: add summarize stage (qwen2.5 via ollama)"
```

---

### Task 6: Pipeline orchestrator + CLI entry point

**Files:**
- Create: `~/.config/nix/pkgs/reel-summarize/reel_summarize/pipeline.py`
- Create: `~/.config/nix/pkgs/reel-summarize/reel_summarize/cli.py`

**Interfaces:**
- Consumes: all stage functions, Config
- Produces: `run(url: str, cfg: Config)` — main pipeline, prints summary to stdout
  `entry()` — argparse CLI

- [ ] **Step 1: Create pipeline.py**

```python
from __future__ import annotations

import os
import shutil
import sys
import tempfile

from reel_summarize.config import Config
from reel_summarize.stages.download import download
from reel_summarize.stages.audio_extract import extract_audio
from reel_summarize.stages.frame_extract import extract_frames
from reel_summarize.stages.transcribe import transcribe, transcribe_text
from reel_summarize.stages.vision import analyze_frames, format_vision_timeline
from reel_summarize.stages.summarize import generate_summary


def run(url: str, cfg: Config, keep_artifacts: bool = False):
    work_dir = tempfile.mkdtemp(prefix="reel-summarize-")

    try:
        print("\u2192 downloading video...", file=sys.stderr)
        down = download(url, work_dir)
        video_path = down["video_path"]
        metadata = down["metadata"]

        print("\u2192 extracting audio...", file=sys.stderr)
        audio_path = extract_audio(video_path, work_dir)

        print("\u2192 extracting frames...", file=sys.stderr)
        frames = extract_frames(video_path, work_dir, cfg)

        print("\u2192 transcribing audio (faster-whisper)...", file=sys.stderr)
        segments = transcribe(audio_path, cfg)
        transcript = transcribe_text(segments)

        vision_results = []
        if frames:
            print(f"\u2192 scanning {len(frames)} frames (qwen2-vl)...", file=sys.stderr)
            vision_results = analyze_frames(frames, cfg)

        vision_timeline = format_vision_timeline(
            frames, vision_results, cfg.frames_per_second
        )

        print("\u2192 summarizing (qwen2.5)...", file=sys.stderr)
        summary = generate_summary(
            transcript=transcript,
            vision_timeline=vision_timeline,
            caption=metadata.get("caption"),
            author=metadata.get("author"),
            cfg=cfg,
        )

        print(summary)

    finally:
        if not keep_artifacts:
            shutil.rmtree(work_dir, ignore_errors=True)
```

- [ ] **Step 2: Create cli.py**

```python
from __future__ import annotations

import argparse
import sys

from reel_summarize.config import Config, load as load_config
from reel_summarize.pipeline import run


def _preflight(cfg: Config):
    import shutil
    import subprocess

    errors = []

    # Check yt-dlp
    if not shutil.which("yt-dlp"):
        errors.append("yt-dlp not found on PATH (install via nix or pip)")

    # Check ffmpeg
    if not shutil.which("ffmpeg"):
        errors.append("ffmpeg not found on PATH (install via nix or brew)")

    # Check ollama
    try:
        import httpx
        resp = httpx.get(f"{cfg.host}/api/tags", timeout=5)
        resp.raise_for_status()
        models = {m["name"] for m in resp.json().get("models", [])}
        if cfg.vision_model not in models:
            errors.append(f"ollama model '{cfg.vision_model}' not pulled (run: ollama pull {cfg.vision_model})")
        if cfg.summarize_model not in models:
            errors.append(f"ollama model '{cfg.summarize_model}' not pulled (run: ollama pull {cfg.summarize_model})")
    except Exception as e:
        errors.append(f"ollama unreachable at {cfg.host}: {e}")

    # Check faster-whisper
    try:
        import faster_whisper  # noqa
    except ImportError:
        errors.append("faster-whisper not available (should be installed by nix package)")

    if errors:
        for e in errors:
            print(f"  \u2716 {e}", file=sys.stderr)
        sys.exit(2)
    else:
        print("  \u2713 all prerequisites met", file=sys.stderr)


def entry():
    parser = argparse.ArgumentParser(
        description="Summarize an Instagram Reel using local models"
    )
    parser.add_argument("url", nargs="?", help="Instagram Reel URL")
    parser.add_argument("--preflight", action="store_true", help="Check prerequisites")
    parser.add_argument("--keep-artifacts", action="store_true",
                        help="Keep intermediate files in /tmp/")
    parser.add_argument("--frames-per-second", type=int, default=None,
                        help="Override frame sampling rate")

    args = parser.parse_args()

    cfg = load_config()
    if args.frames_per_second is not None:
        cfg.frames_per_second = args.frames_per_second

    if args.preflight:
        _preflight(cfg)

    if not args.url:
        parser.print_help()
        sys.exit(1)

    run(args.url, cfg, keep_artifacts=args.keep_artifacts)


if __name__ == "__main__":
    entry()
```

- [ ] **Step 3: Create tests/test_cli.py**

```python
import unittest
from unittest.mock import patch
from reel_summarize.cli import entry


class TestCLI(unittest.TestCase):
    @patch("reel_summarize.cli._preflight")
    def test_preflight_flag(self, mock_preflight):
        with patch("sys.argv", ["reel-summarize", "--preflight"]):
            with self.assertRaises(SystemExit):
                entry()

    @patch("reel_summarize.cli.run")
    def test_run_with_url(self, mock_run):
        with patch("sys.argv", ["reel-summarize", "https://instagram.com/reel/xyz"]):
            entry()
            mock_run.assert_called_once()

    @patch("reel_summarize.cli.run")
    def test_keep_artifacts_flag(self, mock_run):
        with patch("sys.argv", ["reel-summarize", "https://instagram.com/reel/xyz", "--keep-artifacts"]):
            entry()
            args, kwargs = mock_run.call_args
            self.assertTrue(kwargs["keep_artifacts"])
```

- [ ] **Step 4: Create tests for pipeline.py**

```python
import unittest
from unittest.mock import patch, MagicMock
from reel_summarize.config import Config
from reel_summarize.pipeline import run


class TestPipeline(unittest.TestCase):
    @patch("reel_summarize.pipeline.download")
    @patch("reel_summarize.pipeline.extract_audio")
    @patch("reel_summarize.pipeline.extract_frames")
    @patch("reel_summarize.pipeline.transcribe")
    @patch("reel_summarize.pipeline.analyze_frames")
    @patch("reel_summarize.pipeline.generate_summary")
    def test_pipeline_flow(self, mock_summary, mock_vision, mock_transcribe,
                           mock_frames, mock_audio, mock_download):
        mock_download.return_value = {
            "video_path": "/tmp/v.mp4",
            "metadata": {"caption": "test", "author": "user", "duration": 30},
        }
        mock_audio.return_value = "/tmp/audio.wav"
        mock_frames.return_value = ["f1.jpg", "f2.jpg"]
        mock_transcribe.return_value = [{"start": 0.0, "end": 1.0, "text": "hello"}]
        mock_vision.return_value = [{"text": ["hi"], "scene": "test"}]
        mock_summary.return_value = "summary text"

        cfg = Config()
        with patch("builtins.print") as mock_print:
            run("https://instagram.com/reel/xyz", cfg, keep_artifacts=True)
            mock_summary.assert_called_once()
```

- [ ] **Step 5: Verify all tests pass**

Run: `python -m pytest ~/.config/nix/pkgs/reel-summarize/tests/ -v`
Expected: all tests pass

- [ ] **Step 6: Verify CLI help works**

Run: `python -m reel_summarize --help` (from repo root with PYTHONPATH set)
Expected: help text with --preflight, --keep-artifacts, --frames-per-second

- [ ] **Step 7: Commit**

```bash
git add .config/nix/pkgs/reel-summarize/
git commit -m "reel-summarize: add pipeline orchestrator and CLI entry point"
```

---

### Task 7: Nix packaging + dotfiles flake wiring

**Files:**
- Create: `~/.config/nix/pkgs/reel-summarize/default.nix`
- Create: `~/.config/nix/pkgs/reel-summarize/module.nix`
- Create: `~/.config/nix/modules/home/reel-summarize.nix`
- Modify: `~/.config/nix/hosts/accismus/configuration.nix` (add import + enable)

**Interfaces:**
- Consumes: the Python package from previous tasks
- Produces: nix derivation for reel-summarize, home-manager module, accismus enable

- [ ] **Step 1: Create default.nix**

Mirrors what-changed's default.nix but with httpx dep and aarch64-darwin platform.

```nix
{
  lib,
  python3,
}:
python3.pkgs.buildPythonApplication {
  pname = "reel-summarize";
  version = "0.1.0";
  src = ./.;
  format = "pyproject";
  nativeBuildInputs = with python3.pkgs; [setuptools];
  propagatedBuildInputs = with python3.pkgs; [httpx faster-whisper];
  doCheck = false;
  meta = with lib; {
    description = "Summarize Instagram Reels using local models (Ollama + faster-whisper)";
    homepage = "https://github.com/bonds/dotfiles";
    license = licenses.mit;
    platforms = platforms.all;
    maintainers = [];
  };
}
```

- [ ] **Step 2: Create module.nix**

The home-manager module that adds reel-summarize to user packages:

```nix
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.reel-summarize;
in {
  options.programs.reel-summarize = {
    enable = mkEnableOption "reel-summarize — summarize Instagram Reels using local models";

    settings = mkOption {
      type = types.submodule {
        options = {
          host = mkOption {
            type = types.str;
            default = "http://localhost:11434";
            description = "Ollama API host";
          };
          visionModel = mkOption {
            type = types.str;
            default = "qwen2-vl:7b";
            description = "Ollama vision model for per-frame OCR";
          };
          summarizeModel = mkOption {
            type = types.str;
            default = "qwen2.5:7b";
            description = "Ollama model for final summary";
          };
          whisperModel = mkOption {
            type = types.str;
            default = "small";
            description = "Whisper model size (tiny, base, small, medium, large-v3)";
          };
          framesPerSecond = mkOption {
            type = types.int;
            default = 1;
            description = "Frame sampling rate";
          };
          maxFrames = mkOption {
            type = types.int;
            default = 60;
            description = "Maximum frames to analyze";
          };
        };
      };
      default = {};
      description = "Settings written to ~/.config/reel-summarize/config.toml";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [(pkgs.callPackage ../../pkgs/reel-summarize {})];
    home.file.".config/reel-summarize/config.toml".text = let
      s = cfg.settings;
    in ''
      host = "${s.host}"
      vision_model = "${s.visionModel}"
      summarize_model = "${s.summarizeModel}"
      whisper_model = "${s.whisperModel}"
      frames_per_second = ${toString s.framesPerSecond}
      max_frames = ${toString s.maxFrames}
    '';
  };
}
```

- [ ] **Step 3: Create modules/home/reel-summarize.nix**

```nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.reel-summarize;
in {
  options.programs.reel-summarize = {
    enable = lib.mkEnableOption "reel-summarize — summarize Instagram Reels using local models";

    settings = lib.mkOption {
      type = lib.types.submodule {
        options = {
          host = lib.mkOption {
            type = lib.types.str;
            default = "http://localhost:11434";
            description = "Ollama API host";
          };
          visionModel = lib.mkOption {
            type = lib.types.str;
            default = "qwen2-vl:7b";
            description = "Ollama vision model for per-frame OCR";
          };
          summarizeModel = lib.mkOption {
            type = lib.types.str;
            default = "qwen2.5:7b";
            description = "Ollama model for final summary";
          };
          whisperModel = lib.mkOption {
            type = lib.types.str;
            default = "small";
            description = "Whisper model size (tiny, base, small, medium, large-v3)";
          };
          framesPerSecond = lib.mkOption {
            type = lib.types.int;
            default = 1;
            description = "Frame sampling rate";
          };
          maxFrames = lib.mkOption {
            type = lib.types.int;
            default = 60;
            description = "Maximum frames to analyze";
          };
        };
      };
      default = {};
      description = "Settings written to ~/.config/reel-summarize/config.toml";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [(pkgs.callPackage ../../pkgs/reel-summarize {})];
    home.file.".config/reel-summarize/config.toml".text = let
      s = cfg.settings;
    in ''
      host = "${s.host}"
      vision_model = "${s.visionModel}"
      summarize_model = "${s.summarizeModel}"
      whisper_model = "${s.whisperModel}"
      frames_per_second = ${toString s.framesPerSecond}
      max_frames = ${toString s.maxFrames}
    '';
  };
}
```

- [ ] **Step 4: Modify accismus configuration.nix**

Add the import and enable line next to what-changed's entries:

In `~/.config/nix/hosts/accismus/configuration.nix`, around line 240:

```
        ../../modules/home/reel-summarize.nix
      ];
      programs.what-changed.enable = true;
      programs.reel-summarize.enable = true;
```

- [ ] **Step 5: Commit**

```bash
git add .config/nix/pkgs/reel-summarize/ .config/nix/modules/home/reel-summarize.nix .config/nix/hosts/accismus/configuration.nix
git commit -m "reel-summarize: add nix derivation, home-manager module, enable on accismus"
```

---

### Task 8: Opencode skill + docs

**Files:**
- Create: `~/.config/opencode/skills/reel-summarize/SKILL.md`
- Modify: `~/AGENTS.md`

- [ ] **Step 1: Create opencode skill**

```markdown
# Reel Summarizer

Summarize Instagram Reels from a URL. Use when the user shares an Instagram
Reel link and wants to know what it's about without watching it.

**Trigger patterns:**
- User provides a URL containing `instagram.com/reel/` or `instagr.am/reel/`
- User asks "summarize this reel", "what is this reel about", "what's in this Instagram"

**Procedure:**

1. Extract the reel URL from the user's message
2. Run `reel-summarize <url>` via the bash tool
3. Capture stdout (the summary) and stderr (progress messages)
4. Present the summary to the user

**Exit code handling:**
- Exit 0: success — present stdout directly
- Exit 2: missing prerequisite — tell the user to run `ollama pull qwen2-vl:7b qwen2.5:7b`
- Exit 3: download failure — tell the user the URL may be private or expired
- Other exit codes: print the error from stderr

**Notes:**
- Runs entirely locally via Ollama + faster-whisper
- Takes ~30-120s to complete depending on reel length
- Must have ollama running with `qwen2-vl:7b` and `qwen2.5:7b` pulled
- The `reel-summarize` binary is on PATH after `nr`
```

- [ ] **Step 2: Update AGENTS.md**

Add at the end of the AGENTS.md file, under the nix-what-changed section:

```markdown
### reel-summarize
- **New:** Local Instagram Reel summarizer (v0.1.0)
- Python package at `~/.config/nix/pkgs/reel-summarize/`
- Pipeline: yt-dlp download → ffmpeg frames+audio → faster-whisper transcription → qwen2-vl per-frame OCR → qwen2.5 summary
- Nix-managed via home-manager module: `programs.reel-summarize.enable`
- Runtime deps: `yt-dlp`+`ffmpeg` via nix, ollama with `qwen2-vl:7b`+`qwen2.5:7b`
- CLI: `reel-summarize <url>   # concise prose summary to stdout`
- Opencode skill: `~/.config/opencode/skills/reel-summarize/SKILL.md`
- `nix flake check` runs format check, python syntax check, pytest suite (like what-changed)
- Model config at `~/.config/reel-summarize/config.toml`
```

- [ ] **Step 3: Commit**

```bash
git add .config/opencode/skills/reel-summarize/SKILL.md AGENTS.md
git commit -m "reel-summarize: add opencode skill and AGENTS.md docs"
```

---

## Self-review

1. **Spec coverage:** The spec is fully covered: architecture (tasks 1-6), CLI surface (task 6), pipeline stages (tasks 2-5), testing (in each task), nix packaging (task 7), opencode skill (task 8), AGENTS.md docs (task 8).
2. **Placeholder scan:** No TBD, TODO, or missing code in any step.
3. **Type consistency:** Function signatures consistent across pipeline.py → stage functions. `analyze_frames` returns `list[dict]`, `format_vision_timeline` takes `list[str], list[dict], int`. `generate_summary` takes the aggregated strings and metadata.
4. **Missing dependency:** `pipeline.py` imports `shutil` in the `finally` block — should be a top-level import. Fixed in the code above by moving it.
