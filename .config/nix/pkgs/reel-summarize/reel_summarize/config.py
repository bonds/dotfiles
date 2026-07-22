from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, fields

CONFIG_PATH = os.path.expanduser("~/.config/reel-summarize/config.toml")
MODELS_DIR = os.path.expanduser("~/.local/share/transcribe-models")

MODEL_URL = "https://huggingface.co/handy-computer/whisper-small-gguf/resolve/main"


@dataclass
class Config:
    host: str = "http://localhost:8080"
    vision_host: str = "http://localhost:8081"
    backend: str = "openai"  # "openai" (llama.cpp) or "ollama"
    vision_model: str = "qwen2.5-vl:7b"
    summarize_model: str = "qwen2.5:7b"
    whisper_model: str = "whisper-small-Q5_K_M.gguf"
    frames_per_second: int = 1
    max_frames: int = 10
    timeout: int = 180


def resolve_model_name(host: str, cfg: Config) -> str:
    """Query the LLM server for the actual loaded model name."""
    import httpx

    try:
        if cfg.backend == "openai":
            resp = httpx.get(f"{host.rstrip('/')}/v1/models", timeout=5)
            resp.raise_for_status()
            data = resp.json().get("data", [])
            if data:
                return data[0].get("id", cfg.vision_model)
        elif cfg.backend == "ollama":
            resp = httpx.get(f"{host.rstrip('/')}/api/tags", timeout=5)
            resp.raise_for_status()
            models = resp.json().get("models", [])
            if models:
                return models[0].get("name", cfg.vision_model)
    except Exception:
        pass
    return cfg.vision_model


def whisper_model_path(cfg: Config) -> str:
    """Resolve whisper_model to an absolute path.

    If it's already an absolute path, use it as-is. Otherwise treat it as a
    filename inside MODELS_DIR (auto-downloaded on first run).
    """
    if os.path.isabs(cfg.whisper_model):
        return cfg.whisper_model
    return os.path.join(MODELS_DIR, cfg.whisper_model)


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
        "host": "REEL_SUMMARIZE_HOST",
        "vision_host": "REEL_SUMMARIZE_VISION_HOST",
        "backend": "REEL_SUMMARIZE_BACKEND",
        "vision_model": "REEL_SUMMARIZE_VISION_MODEL",
        "summarize_model": "REEL_SUMMARIZE_MODEL",
        "whisper_model": "REEL_SUMMARIZE_WHISPER_MODEL",
        "max_frames": "REEL_SUMMARIZE_MAX_FRAMES",
        "frames_per_second": "REEL_SUMMARIZE_FPS",
        "timeout": "REEL_SUMMARIZE_TIMEOUT",
    }
    for attr, var in env.items():
        val = os.environ.get(var)
        if val is not None:
            fld = next((f for f in fields(cfg) if f.name == attr), None)
            if fld is not None:
                typ = fld.type
                if typ is int:
                    val = int(val)
            setattr(cfg, attr, val)
    return cfg
