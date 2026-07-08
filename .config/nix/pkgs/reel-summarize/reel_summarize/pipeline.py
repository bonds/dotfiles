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
            print(f"→ scanning {len(frames)} frames (llama3.2-vision)...", file=sys.stderr)
            vision_results = analyze_frames(frames, cfg)

        vision_timeline = format_vision_timeline(
            frames, vision_results, cfg.frames_per_second
        )

        print("→ summarizing (qwen2.5)...", file=sys.stderr)
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
