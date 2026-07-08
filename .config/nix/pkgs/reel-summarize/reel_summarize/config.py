from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, fields

CONFIG_PATH = os.path.expanduser("~/.config/reel-summarize/config.toml")


@dataclass
class Config:
    host: str = "http://localhost:11434"
    vision_model: str = "llama3.2-vision:11b"
    summarize_model: str = "qwen2.5:7b"
    whisper_model: str = "small"
    frames_per_second: int = 1
    max_frames: int = 60
    timeout: int = 180


def load(path: str | None = None) -> Config:
    cfg = Config()
    p = path or CONFIG_PATH
    if os.path.exists(p):
        with open(p, "rb") as f:
            raw = tomllib.load(f)
        for fld in fields(cfg):
            if fld.name in raw:
                setattr(cfg, fld.name, raw[fld.name])
    env = {
        "host": "REEL_SUMMARIZE_OLLAMA_HOST",
        "vision_model": "REEL_SUMMARIZE_VISION_MODEL",
        "summarize_model": "REEL_SUMMARIZE_MODEL",
        "whisper_model": "REEL_SUMMARIZE_WHISPER_MODEL",
    }
    for attr, var in env.items():
        val = os.environ.get(var)
        if val is not None:
            setattr(cfg, attr, val)
    return cfg
