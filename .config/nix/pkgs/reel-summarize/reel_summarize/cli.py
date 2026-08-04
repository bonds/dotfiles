from __future__ import annotations

import argparse
import os
import sys

from reel_summarize.config import Config, load as load_config
from reel_summarize.pipeline import run, run_stage


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

    if cfg.backend not in ("openai", "osaurus"):
        try:
            _ensure_ollama_model(cfg.vision_model, cfg)
            _ensure_ollama_model(cfg.summarize_model, cfg)
        except httpx.RequestError as e:
            errors.append(f"LLM unreachable at {cfg.host}: {e}")

    try:
        import transcribe_cpp  # noqa: F401
    except ImportError:
        errors.append("transcribe-cpp not available (should be installed by nix package)")
    except Exception as e:
        # transcribe_cpp import checks the native library — surface that error
        errors.append(f"transcribe-cpp native library error: {e}")

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
    parser.add_argument("--stage", choices=["metadata", "download", "process", "all"], default="all",
                        help="Run only specific stage(s)")
    parser.add_argument("--benchmark", action="store_true",
                        help="Run benchmarks against reference samples")
    parser.add_argument("--benchmark-backends", default=None,
                        help="Comma-separated backends to benchmark (e.g. openai,osaurus)")
    parser.add_argument("--benchmark-samples", default=None,
                        help="Comma-separated sample names (default: all)")
    parser.add_argument("--json", action="store_true",
                        help="Output benchmark results as JSON")
    parser.add_argument("--save", action="store_true",
                        help="Save benchmark results to benchmarks/results/")

    args = parser.parse_args()

    cfg = load_config()
    if args.frames_per_second is not None:
        cfg.frames_per_second = args.frames_per_second

    if args.benchmark:
        from reel_summarize.benchmarks.runner import run_benchmark_cli

        run_benchmark_cli(
            backends=args.benchmark_backends,
            samples=args.benchmark_samples,
            json_output=args.json,
            save=args.save,
        )
        return

    if args.preflight:
        _preflight(cfg)

    if not args.url:
        parser.print_help()
        sys.exit(1)

    if args.stage == "all":
        run(args.url, cfg, keep_artifacts=args.keep_artifacts)
    else:
        run_stage(args.stage, args.url, cfg, keep_artifacts=args.keep_artifacts)


if __name__ == "__main__":
    entry()
