from __future__ import annotations

import fcntl
import json
import os
import shutil
import sys
import tempfile

from reel_summarize.config import Config, whisper_model_path, MODELS_DIR, MODEL_URL
from reel_summarize.stages.download import download, fetch_metadata
from reel_summarize.stages.audio_extract import extract_audio
from reel_summarize.stages.frame_extract import extract_frames
from reel_summarize.stages.transcribe import transcribe, transcribe_text
from reel_summarize.stages.vision import analyze_frames, format_vision_timeline
from reel_summarize.stages.summarize import generate_summary

_LOCK_PATH = os.path.expanduser("~/.cache/reel-summarize.lock")

STAGE_DIR = os.path.join(tempfile.gettempdir(), "reel-summarize-stage")
STATE_FILE = os.path.join(STAGE_DIR, "state.json")


def _ensure_model(cfg: Config, model: str, label: str):
    if cfg.backend == "openai":
        # llama.cpp loads models at server startup — nothing to pull
        return
    _ensure_ollama_model(model, cfg)


def _ensure_ollama_model(model: str, cfg: Config):
    import subprocess
    import httpx

    resp = httpx.get(f"{cfg.host}/api/tags", timeout=10)
    resp.raise_for_status()
    pulled = {m["name"] for m in resp.json().get("models", [])}
    if model in pulled:
        return

    print(f"  → pulling '{model}' (this may take a while)...", file=sys.stderr, flush=True)
    pull_proc = subprocess.run(
        ["ollama", "pull", model],
        timeout=600,
    )
    if pull_proc.returncode != 0:
        print(f"  ✖ failed to pull model '{model}'", file=sys.stderr, flush=True)
        sys.exit(2)


def _ensure_whisper_model(cfg: Config):
    path = whisper_model_path(cfg)
    if os.path.exists(path):
        return

    filename = os.path.basename(path)
    url = f"{MODEL_URL}/{filename}"
    os.makedirs(os.path.dirname(path), exist_ok=True)

    import httpx

    print(f"  → downloading whisper model '{filename}'...", file=sys.stderr, flush=True)
    with httpx.stream("GET", url, timeout=600, follow_redirects=True) as resp:
        resp.raise_for_status()
        with open(path, "wb") as f:
            for chunk in resp.iter_bytes(chunk_size=1024 * 1024):
                f.write(chunk)
    print(f"  ✓ saved to {path}", file=sys.stderr, flush=True)


def _save_state(data: dict):
    os.makedirs(STAGE_DIR, exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(data, f, default=str)


def _load_state() -> dict:
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f:
            return json.load(f)
    return {}


def _clear_state():
    if os.path.exists(STATE_FILE):
        os.unlink(STATE_FILE)


def _acquire_lock():
    os.makedirs(os.path.dirname(_LOCK_PATH), exist_ok=True)
    lock_fd = open(_LOCK_PATH, "w")
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
    return lock_fd


def _release_lock(lock_fd):
    fcntl.flock(lock_fd, fcntl.LOCK_UN)
    lock_fd.close()


def run(url: str, cfg: Config, keep_artifacts: bool = False):
    lock_fd = _acquire_lock()
    work_dir = tempfile.mkdtemp(prefix="reel-summarize-")
    _clear_state()

    try:
        _ensure_model(cfg, cfg.vision_model, "vision")
        _ensure_model(cfg, cfg.summarize_model, "summary")
        _ensure_whisper_model(cfg)

        p = lambda m: print(m, file=sys.stderr, flush=True)

        p("→ downloading video...")
        down = download(url, work_dir)
        video_path = down["video_path"]
        metadata = down["metadata"]
        p("→ done download")

        p("→ extracting audio...")
        audio_path = extract_audio(video_path, work_dir)
        p("→ done audio extract")

        p("→ extracting frames...")
        frames = extract_frames(video_path, work_dir, cfg)
        p(f"→ done frame extract ({len(frames)} frames)")

        p("→ transcribing audio (whisper)...")
        segments = transcribe(audio_path, cfg)
        transcript = transcribe_text(segments)
        p(f"→ done transcribe ({len(transcript)} chars)")

        vision_results = []
        if frames:
            p(f"→ scanning {len(frames)} frames ({cfg.vision_model})...")
            vision_results = analyze_frames(frames, cfg)

        vision_timeline = format_vision_timeline(
            frames, vision_results, cfg.frames_per_second
        )

        author = metadata.get("author") or "unknown"
        caption = metadata.get("caption") or "(no caption)"
        p(f"→ summarizing ({cfg.summarize_model})...")
        summary = generate_summary(
            transcript=transcript,
            vision_timeline=vision_timeline,
            caption=caption,
            author=author,
            cfg=cfg,
        )

        if author:
            print(f"Posted by: {author}", flush=True)
        if caption:
            print(f"Caption: {caption}", flush=True)
        print(flush=True)
        print(summary)

    finally:
        if not keep_artifacts:
            shutil.rmtree(work_dir, ignore_errors=True)
        _release_lock(lock_fd)


def run_stage(stage: str, url: str, cfg: Config, keep_artifacts: bool = False):
    """Run a single stage of the pipeline. Saves intermediate results to a
    shared temp directory so stages can be called incrementally."""
    lock_fd = _acquire_lock()
    state = _load_state()
    work_dir = state.get("work_dir")

    try:
        p = lambda m: print(m, file=sys.stderr, flush=True)

        if stage == "metadata":
            metadata = fetch_metadata(url)
            author = metadata.get("author") or "unknown"
            caption = metadata.get("caption") or "(no caption)"
            if author:
                print(f"Posted by: {author}", flush=True)
            if caption:
                print(f"Caption: {caption}", flush=True)
            _save_state({"metadata": metadata})
            return

        if stage == "download":
            _ensure_model(cfg, cfg.vision_model, "vision")
            _ensure_model(cfg, cfg.summarize_model, "summary")

            state = _load_state()
            metadata = state.get("metadata") if state else None
            if not metadata:
                p("→ fetching metadata...")
                metadata = fetch_metadata(url)
                author = metadata.get("author") or "unknown"
                caption = metadata.get("caption") or "(no caption)"
                if author:
                    print(f"Posted by: {author}", flush=True)
                if caption:
                    print(f"Caption: {caption}", flush=True)

            if not work_dir:
                work_dir = tempfile.mkdtemp(prefix="reel-summarize-")
                _save_state({"work_dir": work_dir, "metadata": metadata})

            p("→ downloading video...")
            down = download(url, work_dir)
            video_path = down["video_path"]

            p("→ extracting frames and audio...")
            frames = extract_frames(video_path, work_dir, cfg)
            audio_path = extract_audio(video_path, work_dir)
            _save_state({
                "work_dir": work_dir,
                "video_path": video_path,
                "audio_path": audio_path,
                "frames": frames,
                "metadata": metadata,
            })
            p(f"✓ download done — {len(frames)} frames, audio extracted")

        elif stage == "process":
            state = _load_state()
            if not state or "work_dir" not in state:
                print("→ no prior download state found — run --stage download first", file=sys.stderr)
                sys.exit(1)

            work_dir = state["work_dir"]
            metadata = state["metadata"]
            video_path = state.get("video_path")
            audio_path = state.get("audio_path")
            frames = state.get("frames", [])

            if not audio_path or not os.path.exists(audio_path):
                p("→ audio not found, re-extracting...")
                audio_path = extract_audio(video_path, work_dir)

            _ensure_whisper_model(cfg)
            p("→ transcribing audio (whisper)...")
            segments = transcribe(audio_path, cfg)
            transcript = transcribe_text(segments)
            p(f"✓ transcription done ({len(transcript)} chars)")

            vision_results = []
            if frames:
                p(f"→ scanning {len(frames)} frames ({cfg.vision_model})...")
                vision_results = analyze_frames(frames, cfg)

            vision_timeline = format_vision_timeline(
                frames, vision_results, cfg.frames_per_second
            )

            author = metadata.get("author") or "unknown"
            caption = metadata.get("caption") or "(no caption)"
            p(f"→ summarizing ({cfg.summarize_model})...")
            summary = generate_summary(
                transcript=transcript,
                vision_timeline=vision_timeline,
                caption=caption,
                author=author,
                cfg=cfg,
            )

            if author:
                print(f"Posted by: {author}", flush=True)
            if caption:
                print(f"Caption: {caption}", flush=True)
            print(flush=True)
            print(summary)
            _clear_state()

    finally:
        if stage == "process" or (not keep_artifacts and stage != "download"):
            if work_dir and os.path.exists(work_dir):
                shutil.rmtree(work_dir, ignore_errors=True)
        _release_lock(lock_fd)
