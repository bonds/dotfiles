from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, fields

CONFIG_PATH = os.path.expanduser("~/.config/what-changed/config.toml")


@dataclass
class Config:
    backend: str = "ollama"
    host: str = "http://localhost:11434"
    model: str = "gemma3:1b-it-qat"
    timeout: int = 180
    max_input_bytes: int = 15000
    max_bullets: int = 5
    max_changelog_bytes: int = 50000
    cache_dir: str = "~/.cache/what-changed"
    gh_timeout: int = 15
    http_timeout: int = 8


def load(path: str | None = None) -> Config:
    cfg = Config()
    p = path or CONFIG_PATH
    if os.path.exists(p):
        with open(p, "rb") as f:
            raw = tomllib.load(f)
        for fld in fields(cfg):
            if fld.name in raw:
                setattr(cfg, fld.name, raw[fld.name])
    return cfg
