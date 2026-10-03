from __future__ import annotations

import glob
import json
import os
import re
import subprocess
import sys
import time
from urllib.parse import urlparse

from reel_summarize.errors import DownloadError

# Hosts treated as YouTube inputs.  ``youtube-nocookie.com`` covers embedded
# players; ``youtu.be`` is the short-link domain.
_YT_HOSTS = {
    "youtube.com",
    "www.youtube.com",
    "m.youtube.com",
    "music.youtube.com",
    "youtube-nocookie.com",
    "www.youtube-nocookie.com",
    "youtu.be",
}


def is_youtube_url(url) -> bool:
    """True when *url* points at YouTube (strict host check, not substring)."""
    if not isinstance(url, str):
        return False
    try:
        host = (urlparse(url).hostname or "").lower()
    except ValueError:
        return False
    return host in _YT_HOSTS or host.endswith(".youtube.com")


def fetch_metadata(url: str) -> dict:
    """Metadata for a YouTube URL: caption/author/duration plus an ``is_live`` flag.

    Mirrors ``stages.download._parse_metadata`` mapping (title/description →
    caption, channel/uploader → author) but keeps the raw JSON so livestreams
    can be rejected before any download starts.
    """
    from reel_summarize.stages.download import _cookies_opt
    from reel_summarize.stages.download import _parse_metadata  # local import, used below

    result = subprocess.run(
        ["yt-dlp", "--dump-json", "--match-filter", "!is_live", *_cookies_opt(), url],
        capture_output=True, text=True, timeout=60,
    )
    if result.returncode != 0:
        err = (result.stderr or result.stdout or "").strip()
        if "is_live" in err or "live" in err.lower():
            raise DownloadError(f"{url} looks like a livestream — wait until it ends, then retry")
        raise DownloadError(f"couldn't fetch metadata for {url}: {err}")

    metadata = _parse_metadata(result.stdout)
    try:
        data = json.loads(result.stdout)
        metadata["is_live"] = bool(
            data.get("is_live") or data.get("live_status") == "is_live"
        )
    except (json.JSONDecodeError, AttributeError):
        metadata["is_live"] = False
    return metadata


def download_audio(url: str, work_dir: str, timeout: int = 300) -> str:
    """yt-dlp audio-only download (``bestaudio`` → wav). Returns the file path.

    The file is written as ``audio_src.<ext>`` (not ``audio.wav``) so a later
    ``extract_audio`` pass can convert it to 16 kHz mono without ffmpeg
    complaining about identical input/output paths.
    """
    from reel_summarize.stages.download import _cookies_opt

    out = os.path.join(work_dir, "audio_src.%(ext)s")
    try:
        result = subprocess.run(
            ["yt-dlp", "-f", "bestaudio/best", "-x", "--audio-format", "wav",
             "--match-filter", "!is_live", "-o", out, *_cookies_opt(), url],
            capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        raise DownloadError(f"yt-dlp timed out after {timeout}s downloading audio from {url}")
    if result.returncode != 0:
        raise DownloadError(
            f"yt-dlp failed to download audio from {url}: "
            f"{(result.stderr or result.stdout or '').strip()}"
        )
    for path in sorted(glob.glob(os.path.join(work_dir, "audio_src.*"))):
        if os.path.isfile(path):
            return path
    raise DownloadError(f"yt-dlp reported success but produced no audio file for {url}")


# --- captions -----------------------------------------------------------------

_VTT_TS = re.compile(
    r"^(\d+):(\d\d):(\d\d)[.,](\d{1,3})\s*-->\s*(\d+):(\d\d):(\d\d)[.,](\d{1,3})"
)
_TAG = re.compile(r"<[^>]+>")


def _ts(h: str, m: str, s: str, ms: str) -> float:
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms.ljust(3, "0")) / 1000


def _parse_vtt(text: str) -> list[dict]:
    """Parse WebVTT into ``{start, end, text}`` segments.

    YouTube's auto-captions use a rolling window (each cue repeats lines from
    the previous one); within a cue we drop any line already present in the
    previous cue so repeated words don't pile up.
    """
    lines = text.splitlines()
    segments: list[dict] = []
    prev_lines: list[str] = []
    i = 0
    while i < len(lines):
        m = _VTT_TS.match(lines[i])
        if not m:
            i += 1
            continue
        start = _ts(m.group(1), m.group(2), m.group(3), m.group(4))
        end = _ts(m.group(5), m.group(6), m.group(7), m.group(8))
        i += 1
        cue: list[str] = []
        while i < len(lines) and lines[i].strip() and not _VTT_TS.match(lines[i]):
            cleaned = _TAG.sub("", lines[i]).strip()
            if cleaned:
                cue.append(cleaned)
            i += 1
        fresh = [l for l in cue if l not in prev_lines]
        prev_lines = cue
        if fresh:
            segments.append({"start": start, "end": end, "text": " ".join(fresh)})
    return segments


def _parse_json3(text: str) -> list[dict]:
    """Parse YouTube's json3 subtitle format into segments."""
    data = json.loads(text)
    events = [e for e in data.get("events", []) if e.get("segs")]
    segments: list[dict] = []
    for idx, ev in enumerate(events):
        t0 = ev.get("tStartMs", 0) / 1000
        if idx + 1 < len(events):
            t1 = events[idx + 1].get("tStartMs", 0) / 1000
        else:
            t1 = t0 + (ev.get("tDurationMs") or 2000) / 1000
        txt = "".join(s.get("utf8", "") for s in ev["segs"]).replace("\n", " ").strip()
        if txt:
            segments.append({"start": t0, "end": max(t0, t1), "text": txt})
    return segments


def _lookup_subtitle(work_dir: str) -> list[dict] | None:
    """Read the first parseable ``caps*.json3|vtt`` file yt-dlp wrote into *work_dir*."""
    files = sorted(
        p for p in glob.glob(os.path.join(work_dir, "caps*"))
        if os.path.isfile(p) and p.endswith((".json3", ".vtt"))
    )
    for path in files:
        try:
            with open(path, encoding="utf-8") as f:
                raw = f.read()
            segments = _parse_json3(raw) if path.endswith(".json3") else _parse_vtt(raw)
        except (json.JSONDecodeError, OSError, UnicodeDecodeError):
            continue
        if segments:
            return segments
    return None


def fetch_captions(url: str, work_dir: str, retries: int = 2, timeout: int = 120) -> list[dict] | None:
    """Download and parse YouTube captions (manual or auto-generated).

    Retries HTTP 429 responses with exponential backoff (5s, 15s).  Returns
    ``None`` — never raises — on any failure (rate limit, no captions,
    network error): the caller falls back to local whisper transcription.
    """
    from reel_summarize.stages.download import _cookies_opt

    backoff = [5, 15]
    for attempt in range(retries + 1):
        try:
            result = subprocess.run(
                ["yt-dlp", "--skip-download", "--write-subs", "--write-auto-subs",
                 "--sub-langs", "en.*", "--sub-format", "json3/vtt/best",
                 "-o", os.path.join(work_dir, "caps.%(ext)s"),
                 *_cookies_opt(), url],
                capture_output=True, text=True, timeout=timeout,
            )
        except (subprocess.TimeoutExpired, OSError) as e:
            print(f"  ⚠ caption attempt {attempt + 1} failed: {e}", file=sys.stderr)
            return None

        err = (result.stderr or "") + (result.stdout or "")
        rate_limited = "429" in err

        if result.returncode != 0 and not rate_limited:
            # No captions / unsupported lang / hard failure — no point retrying,
            # but a partial subtitle file may still have been written; the file
            # lookup below covers that before returning None (whisper fallback).
            print(f"  ⚠ captions unavailable: {err.strip().splitlines()[-1] if err.strip() else 'unknown error'}",
                  file=sys.stderr, flush=True)
            # fall through to the subtitle-file lookup (a partial file may
            # still have been written); otherwise keep retrying on 429s.
            segments = _lookup_subtitle(work_dir)
            if segments:
                return segments

            return None
        if rate_limited and attempt < retries:
            delay = backoff[min(attempt, len(backoff) - 1)]
            print(f"  ⚠ captions rate-limited (429), retrying in {delay}s...",
                  file=sys.stderr, flush=True)
            time.sleep(delay)
            continue
        if rate_limited:
            print("  ⚠ captions still rate-limited after retries — will use local whisper",
                  file=sys.stderr, flush=True)
        return _lookup_subtitle(work_dir)
    return None  # unreachable: the loop returns on every path
