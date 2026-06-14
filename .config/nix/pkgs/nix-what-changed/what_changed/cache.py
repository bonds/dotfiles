from __future__ import annotations

import hashlib
import json
import os

from what_changed.config import Config

CACHE_VERSION = 2


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
    """Get cached (changelog_url, description, homepage) for a package."""
    key = f"meta:{pkg}"
    fp = _path(key, cfg)
    if os.path.exists(fp):
        with open(fp) as f:
            data = json.load(f)
        if data.get("version") == CACHE_VERSION:
            return {k: (None if v == "null" or not v else v) for k, v in data["meta"].items()}
    return None


def set_metadata(pkg: str, meta: dict[str, str | None], cfg: Config):
    key = f"meta:{pkg}"
    fp = _path(key, cfg)
    with open(fp, "w") as f:
        json.dump({
            "version": CACHE_VERSION,
            "pkg": pkg,
            "meta": {k: (v or "null") for k, v in meta.items()},
        }, f)
