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
