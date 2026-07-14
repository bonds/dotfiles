from __future__ import annotations

import fcntl
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

_LOCK_PATH = os.path.expanduser("~/.cache/reel-summarize.lock")


def _acquire_lock():
    os.makedirs(os.path.dirname(_LOCK_PATH), exist_ok=True)
    lock_fd = open(_LOCK_PATH, "w")
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
    return lock_fd


def _release_lock(lock_fd):
    fcntl.flock(lock_fd, fcntl.LOCK_UN)
    lock_fd.close()


def _ensure_ollama_model(model: str, cfg: Config):
    import subprocess

    import httpx

    resp = httpx.get(f"{cfg.host}/api/tags", timeout=10)
    resp.raise_for_status()
    pulled = {m["name"] for m in resp.json().get("models", [])}
    if model in pulled:
        return

    print(f"  → pulling '{model}' (this may take a while)...", file=sys.stderr)
    pull_proc = subprocess.run(
        ["ollama", "pull", model],
        timeout=600,
    )
    if pull_proc.returncode != 0:
        print(f"  ✖ failed to pull model '{model}'", file=sys.stderr)
        sys.exit(2)


def run(url: str, cfg: Config, keep_artifacts: bool = False):
    lock_fd = _acquire_lock()
    work_dir = tempfile.mkdtemp(prefix="reel-summarize-")

    try:
        _ensure_ollama_model(cfg.vision_model, cfg)
        _ensure_ollama_model(cfg.summarize_model, cfg)

        print("→ downloading video...", file=sys.stderr)
        down = download(url, work_dir)
        video_path = down["video_path"]
        metadata = down["metadata"]

        print("→ extracting audio...", file=sys.stderr)
        audio_path = extract_audio(video_path, work_dir)

        print("→ extracting frames...", file=sys.stderr)
        frames = extract_frames(video_path, work_dir, cfg)

        print("→ transcribing audio (whisper)...", file=sys.stderr)
        segments = transcribe(audio_path, cfg)
        transcript = transcribe_text(segments)

        vision_results = []
        if frames:
            print(f"→ scanning {len(frames)} frames ({cfg.vision_model})...", file=sys.stderr)
            vision_results = analyze_frames(frames, cfg)

        vision_timeline = format_vision_timeline(
            frames, vision_results, cfg.frames_per_second
        )

        print(f"→ summarizing ({cfg.summarize_model})...", file=sys.stderr)
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
        _release_lock(lock_fd)
