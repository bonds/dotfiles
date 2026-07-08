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
