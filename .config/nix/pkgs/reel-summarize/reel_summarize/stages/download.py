from __future__ import annotations

import json
import os
import sqlite3
import shutil
import subprocess
import sys
import tempfile


def _extract_zen_cookies(container_id: str = "1") -> str | None:
    """Extract cookies from Zen browser's personal workspace into a Netscape-format temp file."""
    base = os.path.expanduser("~/Library/Application Support/zen/Profiles")
    if not os.path.isdir(base):
        return None
    try:
        profiles = [d for d in os.listdir(base) if os.path.isdir(os.path.join(base, d))]
    except PermissionError:
        return None

    for prof in profiles:
        db_path = os.path.join(base, prof, "cookies.sqlite")
        if not os.path.exists(db_path):
            continue
        try:
            dst = tempfile.mktemp(suffix=".sqlite")
            shutil.copy2(db_path, dst)
            conn = sqlite3.connect(dst)
            cur = conn.cursor()
            origin = f"^userContextId={container_id}"
            rows = cur.execute(
                "SELECT host, path, isSecure, expiry, name, value "
                "FROM moz_cookies WHERE originAttributes=? AND host LIKE '%instagram.com' AND expiry > 0",
                (origin,),
            ).fetchall()
            conn.close()
            os.unlink(dst)
            if not rows:
                continue

            out = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
            out.write("# Netscape HTTP Cookie File\n")
            for host, path, isSecure, expiry, name, value in rows:
                domain = host if host.startswith(".") else f".{host}"
                secure = "TRUE" if isSecure else "FALSE"
                exp_sec = int(expiry / 1000)
                out.write(f"{domain}\tTRUE\t{path}\t{secure}\t{exp_sec}\t{name}\t{value}\n")
            out.close()
            return out.name
        except (sqlite3.Error, OSError, shutil.Error):
            continue
    return None


def _cookies_opt() -> list[str]:
    cookies_file = os.environ.get("REEL_SUMMARIZE_COOKIES")
    if cookies_file:
        return ["--cookies", cookies_file]
    zen_cookies = _extract_zen_cookies()
    if zen_cookies:
        return ["--cookies", zen_cookies]
    return []


def _parse_metadata(raw: str | None) -> dict:
    metadata = {"caption": None, "author": None, "duration": None}
    if not raw:
        return metadata
    try:
        data = json.loads(raw)
        metadata["caption"] = data.get("description") or data.get("title")
        metadata["author"] = data.get("uploader") or data.get("channel")
        metadata["duration"] = data.get("duration")
    except json.JSONDecodeError:
        pass
    return metadata


def fetch_metadata(url: str) -> dict:
    """Fetch only the metadata (caption, author, duration) without downloading video. Fast (~1-2s)."""
    meta_result = subprocess.run(
        ["yt-dlp", "--dump-json", *_cookies_opt(), url],
        capture_output=True, text=True, timeout=30,
    )
    if meta_result.returncode != 0:
        print(f"  metadata fetch error: {meta_result.stderr.strip() or meta_result.stdout.strip()}", file=sys.stderr)
        sys.exit(3)
    return _parse_metadata(meta_result.stdout)


def download(url: str, work_dir: str) -> dict:
    video_path = os.path.join(work_dir, "reel.mp4")
    meta_path = os.path.join(work_dir, "metadata.json")

    cookies_opt = _cookies_opt()

    result = subprocess.run(
        ["yt-dlp", "-o", video_path, "--print", "after_move:%(filename)s", *cookies_opt, url],
        capture_output=True, text=True, timeout=300,
    )
    if result.returncode != 0:
        print(f"  yt-dlp error: {result.stderr.strip() or result.stdout.strip()}", file=sys.stderr)
        sys.exit(3)

    meta_result = subprocess.run(
        ["yt-dlp", "--dump-json", *cookies_opt, url],
        capture_output=True, text=True, timeout=30,
    )
    metadata = _parse_metadata(meta_result.stdout if meta_result.returncode == 0 else None)

    with open(meta_path, "w") as f:
        json.dump(metadata, f)

    return {"video_path": video_path, "metadata": metadata}
