from __future__ import annotations

import hashlib
import json
import os

from what_changed.config import Config

CACHE_VERSION = 2

# How long (seconds) a discovered/guessed changelog URL is trusted before we
# re-guess, and how long a "no changelog found" result is trusted before we
# try again (e.g. a changelog may appear later).
GUESS_TTL = 7 * 24 * 3600  # 7 days


def _dir(cfg: Config) -> str:
    d = os.path.expanduser(cfg.cache_dir)
    os.makedirs(d, exist_ok=True)
    return d


def _path(key: str, cfg: Config) -> str:
    h = hashlib.sha256(key.encode()).hexdigest()
    return os.path.join(_dir(cfg), f"{h}.json")


def get_summary(pkg: str, old_ver: str, new_ver: str, cfg: Config) -> list[str] | None:
    key = f"summary:{cfg.prompt_style}:{pkg}:{old_ver}->{new_ver}"
    fp = _path(key, cfg)
    if os.path.exists(fp):
        with open(fp) as f:
            data = json.load(f)
        if data.get("version") == CACHE_VERSION:
            return data.get("bullets")
    return None


def set_summary(pkg: str, old_ver: str, new_ver: str, bullets: list[str] | None, cfg: Config):
    key = f"summary:{cfg.prompt_style}:{pkg}:{old_ver}->{new_ver}"
    fp = _path(key, cfg)
    with open(fp, "w") as f:
        json.dump({
            "version": CACHE_VERSION,
            "pkg": pkg,
            "old_ver": old_ver,
            "new_ver": new_ver,
            "bullets": bullets,
        }, f)


def get_changelog(url: str, cfg: Config) -> str | None:
    key = f"changelog:{url}"
    fp = _path(key, cfg)
    if os.path.exists(fp):
        with open(fp) as f:
            data = json.load(f)
        if data.get("version") == CACHE_VERSION:
            return data.get("text")
    return None


def set_changelog(url: str, text: str | None, cfg: Config):
    key = f"changelog:{url}"
    fp = _path(key, cfg)
    with open(fp, "w") as f:
        json.dump({
            "version": CACHE_VERSION,
            "url": url,
            "text": text,
        }, f)


def get_metadata(pkg: str, cfg: Config) -> dict[str, str | None] | None:
    """Get cached (changelog_url, description, homepage, guessed_url) for a package."""
    key = f"meta:{pkg}"
    fp = _path(key, cfg)
    if os.path.exists(fp):
        with open(fp) as f:
            data = json.load(f)
        if data.get("version") == CACHE_VERSION:
            meta = dict(data["meta"])
            # Normalize stored strings back; keep guessed_at as int.
            for k, v in list(meta.items()):
                if k == "guessed_at":
                    try:
                        meta[k] = int(v)
                    except (TypeError, ValueError):
                        meta[k] = 0
                else:
                    meta[k] = None if v in ("null", None, "") else v
            return meta
    return None


def set_metadata(pkg: str, meta: dict[str, str | None], cfg: Config):
    key = f"meta:{pkg}"
    fp = _path(key, cfg)
    stored = {}
    for k, v in meta.items():
        if k == "guessed_at":
            stored[k] = int(v or 0)
        else:
            stored[k] = v or "null"
    with open(fp, "w") as f:
        json.dump({
            "version": CACHE_VERSION,
            "pkg": pkg,
            "meta": stored,
        }, f)


def invalidate_metadata_guess(pkg: str, cfg: Config):
    """Forget a cached guessed changelog URL for a package so it gets re-searched.

    Keeps description/homepage/metadata-changelog intact; only clears the
    auto-discovered URL (and its timestamp).
    """
    meta = get_metadata(pkg, cfg)
    if meta:
        meta.pop("guessed_url", None)
        meta.pop("guessed_at", None)
        set_metadata(pkg, meta, cfg)
