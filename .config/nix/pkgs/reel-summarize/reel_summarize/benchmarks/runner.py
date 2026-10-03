"""Benchmark runner for reel-summarize backends.

Usage:
    python -m reel_summarize.benchmarks.runner
    python -m reel_summarize.benchmarks.runner --backends openai,osaurus
    python -m reel_summarize.benchmarks.runner --samples reel-001 --json --save
"""

from __future__ import annotations

import datetime
import json
import os
import sys
import time

from reel_summarize.benchmarks.scoring import (
    BenchmarkResult,
    SummaryMetrics,
    Timer,
    VisionMetrics,
    word_count,
)
from reel_summarize.config import Config, load as load_config

SAMPLES_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "benchmarks", "samples")
RESULTS_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "benchmarks", "results")
SAMPLES_JSON = os.path.join(os.path.dirname(__file__), "samples.json")


def _load_sample_defs() -> dict:
    with open(SAMPLES_JSON) as f:
        return json.load(f)


def _load_sample_frames(sample_id: str) -> list[str]:
    """Load pre-extracted frame paths for a sample."""
    frames_dir = os.path.join(SAMPLES_DIR, sample_id)
    if not os.path.isdir(frames_dir):
        return []
    frames = sorted(
        os.path.join(frames_dir, f)
        for f in os.listdir(frames_dir)
        if f.endswith(".jpg")
    )
    return frames


def _load_sample_metadata(sample_id: str) -> dict:
    meta_path = os.path.join(SAMPLES_DIR, sample_id, "metadata.json")
    if os.path.exists(meta_path):
        with open(meta_path) as f:
            return json.load(f)
    return {}


def _load_sample_transcript(sample_id: str) -> str:
    transcript_path = os.path.join(SAMPLES_DIR, sample_id, "transcript.txt")
    if os.path.exists(transcript_path):
        with open(transcript_path) as f:
            return f.read().strip()
    return ""


def _make_config_for_backend(backend: str) -> Config:
    """Create a Config for a specific backend, using auto-discovery for osaurus."""
    cfg = load_config("/nonexistent")  # load defaults only
    cfg.backend = backend
    if backend == "osaurus":
        from reel_summarize.config import discover_osaurus

        discovered = discover_osaurus()
        if discovered:
            cfg.host = discovered
        else:
            cfg.host = "http://127.0.0.1:1337"
        cfg.timeout = 600  # ZAYA1-VL is slow, ~190s per frame
    elif backend == "ollama":
        cfg.host = "http://localhost:11434"
    else:
        cfg.host = "http://localhost:8080"
        cfg.vision_host = "http://localhost:8081"
    return cfg


def _resolve_backend_model(backend: str, cfg: Config) -> str:
    """Get the model name for display purposes."""
    from reel_summarize.config import resolve_model_name

    if backend == "osaurus":
        return resolve_model_name(cfg.host, cfg)
    if backend == "openai":
        return resolve_model_name(cfg.host, cfg)
    return cfg.vision_model


def _osaurus_has_vision(host: str, api_key: str) -> bool:
    """Check if any loaded Osaurus model supports vision."""
    import httpx

    try:
        resp = httpx.get(
            f"{host.rstrip('/')}/v1/models",
            headers={"Authorization": f"Bearer {api_key}"} if api_key else {},
            timeout=5,
        )
        resp.raise_for_status()
        models = resp.json().get("data", [])
        vision_keywords = ["vl", "vision", "llava"]
        return any(
            any(kw in m.get("id", "").lower() for kw in vision_keywords)
            for m in models
        )
    except Exception:
        return False


def run_sample(sample_id: str, sample_def: dict, backends: list[str]) -> list[BenchmarkResult]:
    """Run one sample across multiple backends and return results."""
    frames = _load_sample_frames(sample_id)
    if not frames:
        print(f"  ✖ no frames found for sample '{sample_id}'", file=sys.stderr)
        return []

    metadata = _load_sample_metadata(sample_id)
    transcript = _load_sample_transcript(sample_id)
    results = []

    for backend in backends:
        cfg = _make_config_for_backend(backend)
        model = _resolve_backend_model(backend, cfg)

        # Check if Osaurus has a vision model
        has_vision = True
        if backend == "osaurus":
            has_vision = _osaurus_has_vision(cfg.host, cfg.osaurus_api_key)
            if not has_vision:
                print(f"  \033[33m{backend}\033[m ({model}) — no vision model loaded, skipping vision", file=sys.stderr, flush=True)

        print(f"  \033[1m{backend}\033[m ({model}) on {sample_id}...", file=sys.stderr, flush=True)

        # --- Vision stage ---
        from reel_summarize.stages.vision import analyze_frames, format_vision_timeline

        vision_metrics = VisionMetrics()
        vision_results = []
        vision_timeline = ""

        if has_vision:
            with Timer() as t:
                # Patch analyze_frames to collect per-frame timing
                import reel_summarize.stages.vision as vision_mod

                original_call = None
                if backend == "osaurus":
                    original_call = vision_mod._call_osaurus_vision
                elif backend == "openai":
                    original_call = vision_mod._call_openai_vision
                else:
                    original_call = vision_mod._call_ollama_vision

                def timed_call(image_b64, cfg_ref):
                    with Timer() as ft:
                        result = original_call(image_b64, cfg_ref)
                    vision_metrics.per_frame_s.append(ft.elapsed)
                    # Check if JSON parsing succeeded (non-empty text or scene)
                    if result.get("text") or result.get("scene"):
                        vision_metrics.json_ok += 1
                    else:
                        vision_metrics.json_fail += 1
                    return result

                # Temporarily swap the caller
                if backend == "osaurus":
                    vision_mod._call_osaurus_vision = timed_call
                elif backend == "openai":
                    vision_mod._call_openai_vision = timed_call
                else:
                    vision_mod._call_ollama_vision = timed_call

                try:
                    vision_results = analyze_frames(frames, cfg)
                except SystemExit:
                    vision_metrics.errors += 1
                    vision_results = [{"text": [], "scene": ""}] * len(frames)
                finally:
                    # Restore original
                    if backend == "osaurus":
                        vision_mod._call_osaurus_vision = original_call
                    elif backend == "openai":
                        vision_mod._call_openai_vision = original_call
                    else:
                        vision_mod._call_ollama_vision = original_call

            vision_metrics.total_time_s = round(t.elapsed, 2)
            vision_timeline = format_vision_timeline(frames, vision_results, cfg.frames_per_second)

        # --- Summary stage ---
        from reel_summarize.stages.summarize import generate_summary

        summary_metrics = SummaryMetrics()
        author = metadata.get("author", "unknown")
        caption = metadata.get("caption", "(no caption)")
        with Timer() as t:
            try:
                summary_text = generate_summary(
                    transcript=transcript,
                    vision_timeline=vision_timeline,
                    caption=caption,
                    author=author,
                    cfg=cfg,
                )
                summary_metrics.word_count = word_count(summary_text)
            except SystemExit:
                summary_metrics.error = True
                summary_text = ""
        summary_metrics.time_s = round(t.elapsed, 2)

        result = BenchmarkResult(
            backend=backend,
            model=model,
            sample=sample_id,
            vision=vision_metrics,
            summary=summary_metrics,
            output_text=summary_text,
        )
        results.append(result)

        status = "\033[32mOK\033[m" if not summary_metrics.error else "\033[31mFAIL\033[m"
        print(
            f"    vision {vision_metrics.total_time_s:>5.1f}s  "
            f"summary {summary_metrics.time_s:>5.1f}s  "
            f"json {vision_metrics.json_ok_rate}  "
            f"{summary_metrics.word_count} words  {status}",
            file=sys.stderr,
        )

    return results


def print_table(results: list[BenchmarkResult]):
    """Print a human-readable summary table."""
    print()
    print(
        f"{'Backend':<20s} {'Model':<25s} {'Sample':<12s} "
        f"{'Vision':>7s} {'Summary':>8s} {'Total':>7s} {'JSON':>6s} {'Words':>6s}"
    )
    print(
        f"{'-'*20} {'-'*25} {'-'*12} "
        f"{'-'*7} {'-'*8} {'-'*7} {'-'*6} {'-'*6}"
    )
    for r in results:
        print(
            f"{r.backend:<20s} {r.model:<25s} {r.sample:<12s} "
            f"{r.vision.total_time_s:>6.1f}s {r.summary.time_s:>7.1f}s "
            f"{r.total_time_s:>6.1f}s {r.vision.json_ok_rate:>6s} "
            f"{r.summary.word_count:>5d}"
        )

    # Print summaries for human review
    print()
    for r in results:
        print(f"--- {r.backend}/{r.model} on {r.sample} ---")
        if r.output_text:
            print(r.output_text)
        else:
            print("(no output)")
        print()


def save_results(results: list[BenchmarkResult]):
    """Save results to benchmarks/results/ as JSON."""
    os.makedirs(RESULTS_DIR, exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    backends_str = "_".join(sorted(set(r.backend for r in results)))
    fname = f"{ts}__{backends_str}.json"
    filepath = os.path.join(RESULTS_DIR, fname)

    data = []
    for r in results:
        data.append({
            "backend": r.backend,
            "model": r.model,
            "sample": r.sample,
            "vision_time_s": r.vision.total_time_s,
            "vision_per_frame_s": round(r.vision.avg_per_frame_s, 3),
            "json_ok": r.vision.json_ok,
            "json_fail": r.vision.json_fail,
            "summary_time_s": r.summary.time_s,
            "total_time_s": round(r.total_time_s, 2),
            "word_count": r.summary.word_count,
            "output_text": r.output_text,
        })

    with open(filepath, "w") as f:
        json.dump(data, f, indent=2)
    print(f"  Saved: {filepath}", file=sys.stderr)


def run_benchmark_cli(
    backends: str | None = None,
    samples: str | None = None,
    json_output: bool = False,
    save: bool = False,
):
    """CLI entry point for benchmarks."""
    sample_defs = _load_sample_defs()

    backend_list = (
        [b.strip() for b in backends.split(",")]
        if backends
        else ["openai"]
    )
    sample_list = (
        [s.strip() for s in samples.split(",")]
        if samples
        else list(sample_defs.keys())
    )

    all_results = []
    for sample_id in sample_list:
        if sample_id not in sample_defs:
            print(f"  ✖ unknown sample '{sample_id}'", file=sys.stderr)
            continue
        results = run_sample(sample_id, sample_defs[sample_id], backend_list)
        all_results.extend(results)

    if json_output:
        print(json.dumps([
            {
                "backend": r.backend,
                "model": r.model,
                "sample": r.sample,
                "vision_time_s": r.vision.total_time_s,
                "vision_per_frame_s": round(r.vision.avg_per_frame_s, 3),
                "json_ok": r.vision.json_ok,
                "json_fail": r.vision.json_fail,
                "summary_time_s": r.summary.time_s,
                "total_time_s": round(r.total_time_s, 2),
                "word_count": r.summary.word_count,
                "output_text": r.output_text,
            }
            for r in all_results
        ], indent=2))
    else:
        print_table(all_results)

    if save and all_results:
        save_results(all_results)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Benchmark reel-summarize backends")
    parser.add_argument("--backends", default=None, help="Comma-separated backends")
    parser.add_argument("--samples", default=None, help="Comma-separated sample IDs")
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--save", action="store_true", help="Save results")
    args = parser.parse_args()

    run_benchmark_cli(
        backends=args.backends,
        samples=args.samples,
        json_output=args.json,
        save=args.save,
    )
