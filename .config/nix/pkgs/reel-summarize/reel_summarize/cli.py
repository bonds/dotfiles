from __future__ import annotations

import argparse
import sys

from reel_summarize.config import Config, load as load_config
from reel_summarize.pipeline import run


def _ensure_ollama_model(model: str, cfg: Config):
    import httpx
    import subprocess

    resp = httpx.get(f"{cfg.host}/api/tags", timeout=10)
    resp.raise_for_status()
    pulled = {m["name"] for m in resp.json().get("models", [])}
    if model in pulled:
        return

    print(f"  → pulling '{model}' (this may take a while)...", file=sys.stderr)
    pull_proc = subprocess.run(
        ["ollama", "pull", model],
        timeout=600,
    )
    if pull_proc.returncode != 0:
        print(f"  ✖ failed to pull model '{model}'", file=sys.stderr)
        sys.exit(2)


def _preflight(cfg: Config):
    import shutil

    import httpx

    errors = []

    if not shutil.which("yt-dlp"):
        errors.append("yt-dlp not found on PATH (install via nix or pip)")

    if not shutil.which("ffmpeg"):
        errors.append("ffmpeg not found on PATH (install via nix or brew)")

    try:
        _ensure_ollama_model(cfg.vision_model, cfg)
        _ensure_ollama_model(cfg.summarize_model, cfg)
    except httpx.RequestError as e:
        errors.append(f"ollama unreachable at {cfg.host}: {e}")

    try:
        import whisper  # noqa: F401
    except ImportError:
        errors.append("whisper not available (should be installed by nix package)")

    if errors:
        for e in errors:
            print(f"  ✖ {e}", file=sys.stderr)
        sys.exit(2)
    else:
        print("  ✓ all prerequisites met", file=sys.stderr)


def entry():
    parser = argparse.ArgumentParser(
        description="Summarize an Instagram Reel using local models"
    )
    parser.add_argument("url", nargs="?", help="Instagram Reel URL")
    parser.add_argument("--preflight", action="store_true", help="Check prerequisites")
    parser.add_argument("--keep-artifacts", action="store_true",
                        help="Keep intermediate files in /tmp/")
    parser.add_argument("--frames-per-second", type=int, default=None,
                        help="Override frame sampling rate")

    args = parser.parse_args()

    cfg = load_config()
    if args.frames_per_second is not None:
        cfg.frames_per_second = args.frames_per_second

    if args.preflight:
        _preflight(cfg)

    if not args.url:
        parser.print_help()
        sys.exit(1)

    run(args.url, cfg, keep_artifacts=args.keep_artifacts)


if __name__ == "__main__":
    entry()
