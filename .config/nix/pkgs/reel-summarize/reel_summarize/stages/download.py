from __future__ import annotations

import json
import os
import subprocess
import sys


def download(url: str, work_dir: str) -> dict:
    video_path = os.path.join(work_dir, "reel.mp4")
    meta_path = os.path.join(work_dir, "metadata.json")

    result = subprocess.run(
        ["yt-dlp", "-o", video_path, "--print", "after_move:%(filename)s", url],
        capture_output=True, text=True, timeout=300,
    )
    if result.returncode != 0:
        print(f"  yt-dlp error: {result.stderr.strip() or result.stdout.strip()}", file=sys.stderr)
        sys.exit(3)

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

    with open(meta_path, "w") as f:
        json.dump(metadata, f)

    return {"video_path": video_path, "metadata": metadata}
