from __future__ import annotations

import glob
import json
import os
import tomllib
from dataclasses import dataclass, fields

CONFIG_PATH = os.path.expanduser("~/.config/reel-summarize/config.toml")
MODELS_DIR = os.path.expanduser("~/.local/share/transcribe-models")

MODEL_URL = "https://huggingface.co/handy-computer/whisper-small-gguf/resolve/main"

OSAURUS_CONFIG_GLOB = os.path.expanduser(
    "~/Library/Application Support/com.dinoki.osaurus/SharedConfiguration/*/configuration.json"
)


@dataclass
class Config:
    host: str = "http://localhost:8080"
    vision_host: str = "http://localhost:8081"
    backend: str = "openai"  # "openai" (llama.cpp), "ollama", or "osaurus"
    vision_model: str = "qwen2.5-vl:7b"
    summarize_model: str = "qwen2.5:7b"
    whisper_model: str = "whisper-small-Q5_K_M.gguf"
    frames_per_second: int = 1
    max_frames: int = 10
    timeout: int = 180
    osaurus_api_key: str = ""

    def __post_init__(self):
        # Auto-load Osaurus API key from file if not set
        if not self.osaurus_api_key:
            key_path = os.path.expanduser("~/.config/reel-summarize/osaurus-api-key")
            if os.path.exists(key_path):
                with open(key_path) as f:
                    self.osaurus_api_key = f.read().strip()


def discover_osaurus() -> str | None:
    """Discover a running Osaurus instance via its SharedConfiguration files.

    Returns the base URL (e.g. ``http://127.0.0.1:1337``) or ``None`` if no
    running instance is found.
    """
    candidates = []
    for path in glob.glob(OSAURUS_CONFIG_GLOB):
        try:
            with open(path) as f:
                cfg = json.load(f)
            if cfg.get("health") != "running":
                continue
            port = cfg.get("port")
            address = cfg.get("address")
            if not port or not address:
                continue
            updated = cfg.get("updatedAt", "")
            try:
                import datetime

                ts = datetime.datetime.fromisoformat(updated)
                sort_key = ts.timestamp()
            except Exception:
                sort_key = 0
            candidates.append((sort_key, f"http://{address}:{port}"))
        except Exception:
            continue
    if not candidates:
        return None
    candidates.sort(key=lambda c: c[0], reverse=True)
    return candidates[0][1]


def resolve_model_name(host: str, cfg: Config) -> str:
    """Pick the best model to use for a given LLM server.

    Prefers an explicitly configured ``cfg.summarize_model`` when that model
    is served; otherwise falls back to a non-reasoning (non-"ternary") model.
    """
    import httpx

    try:
        if cfg.backend in ("openai", "osaurus"):
            resp = httpx.get(f"{host.rstrip('/')}/v1/models", timeout=5)
            resp.raise_for_status()
            ids = [m.get("id", "") for m in resp.json().get("data", [])]
            if not ids:
                return cfg.summarize_model
            # Respect an explicitly-configured model if the server offers it.
            if cfg.summarize_model in ids:
                return cfg.summarize_model
            # Prefer non-reasoning models (skip "ternary" models that eat tokens on thinking)
            for mid in ids:
                if "ternary" not in mid.lower():
                    return mid
            return ids[0]
        elif cfg.backend == "ollama":
            resp = httpx.get(f"{host.rstrip('/')}/api/tags", timeout=5)
            resp.raise_for_status()
            models = resp.json().get("models", [])
            if models:
                names = [m.get("name", "") for m in models]
                if cfg.summarize_model in names:
                    return cfg.summarize_model
                return names[0] if names else cfg.summarize_model
    except Exception:
        pass
    return cfg.summarize_model


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
    # Auto-discover Osaurus if backend is set to "osaurus" and host is default
    if cfg.backend == "osaurus" and cfg.host == "http://localhost:8080":
        discovered = discover_osaurus()
        if discovered:
            cfg.host = discovered

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
        "osaurus_api_key": "REEL_SUMMARIZE_OSAURUS_API_KEY",
    }
    for attr, var in env.items():
        val = os.environ.get(var)
        if val is not None:
            fld = next((f for f in fields(cfg) if f.name == attr), None)
            if fld is not None:
                typ = fld.type
                # Python 3.13 dataclasses return the annotation as a *string*
                # ("int"), not the builtin, so compare against both forms.
                if typ in ("int", int):
                    val = int(val)
                elif typ in ("float", float):
                    val = float(val)
            setattr(cfg, attr, val)
    return cfg
