"""Benchmark different LLM models for changelog summarization.

Usage:
    python -m what_changed.benchmark                          # all models, all samples
    python -m what_changed.benchmark --models qwen2.5:1.5b     # specific models
    python -m what_changed.benchmark --samples capstone,hugo   # specific sample
    python -m what_changed.benchmark --json                     # machine-readable output
"""

from __future__ import annotations

import argparse
import asyncio
import datetime
import json
import re
import subprocess
import sys
import time

from what_changed.config import Config
from what_changed.summarize import KNOWN_MERGES, _parse_bullets, _postprocess, summarize

REFERENCE = {
    "capstone": {
        "text": """## What's Changed
* Set correct version number in `CS_VERSION_EXTRA`.
* Backports of CVE fixes and #2935 by @Rot127 in https://github.com/capstone-engine/capstone/pull/2937
**Full Changelog**: https://github.com/capstone-engine/capstone/compare/v5.0.7...v5.0.9""",
        "package": "capstone",
        "expected_bullets": 2,
    },
    "hugo": {
        "text": """## What's Changed
* modules/npm: Fix false stale warning after npm pack 59f35cd9 @jmooring
* Revert "tpl/collections: Make dict return nil when no values are provided" c2709750 @bep
* tpl/time: Fix locale-specific month abbreviations 481b5c5 @jmooring""",
        "package": "hugo",
        "expected_bullets": 3,
    },
    "ollama": {
        "text": """## What's Changed
* Fixed the `gemma4:12b` floating point exception crash on x86, CUDA, Linux, and Windows systems.
* `ollama launch hermes-desktop` now launches Hermes Desktop and can skip rebuilding when a packaged app is already installed.
* Native Windows installation support via Hermes Power Shell installer added.
* Cline CLI integration docs were added.""",
        "package": "ollama",
        "expected_bullets": 4,
    },
    "nixpkgs-2605": {
        "text": """# Release 26.05 ("Yarara", 2026.05/30)

## Highlights
- Stage 1 (a.k.a. initrd) is now based on systemd by default.
- The old scripted initrd implementation is deprecated.

## Backward Incompatibilities
- The `boot` package has been removed.
- Python 2 interpreter is now exclusively housed within the `resholve` package.

## New Modules
- `tranquil`: ATProto PDS implementation.
- `flap`: BGP flapping event detection.""",
        "package": "nixpkgs",
        "expected_bullets": 3,
    },
}


def count_merges(text: str) -> int:
    """Count known word merges in text."""
    count = 0
    for wrong in KNOWN_MERGES:
        count += text.count(wrong)
    # Also count doubled first letters (ssystemd, iinto)
    count += len(re.findall(r"\b(\w)\1(\w{2,})\b", text))
    return count


def score_bullets(bullets: list[str], expected: int) -> float:
    """Score bullet quality: 1.0 = ideal, 0.0 = terrible."""
    n = len(bullets)
    if n == 0:
        return 0.0
    # Ideal: within 1 of expected
    if abs(n - expected) <= 1:
        return 1.0
    # OK: within 2 of expected
    if abs(n - expected) <= 2:
        return 0.6
    # Poor: way off
    return 0.2


def _model_size(model: str) -> str:
    try:
        r = subprocess.run(["ollama", "list"], capture_output=True, text=True, timeout=10)
        for line in r.stdout.splitlines():
            if model in line:
                parts = line.split()
                if len(parts) >= 3:
                    return parts[2]
    except Exception:
        pass
    return "?"


async def run_sample(cfg: Config, name: str, sample: dict) -> dict:
    """Run one model on one sample and return metrics."""
    text = sample["text"]
    pkg = sample["package"]
    expected = sample["expected_bullets"]

    start = time.monotonic()
    bullets = await summarize(pkg, text, cfg)
    elapsed = time.monotonic() - start

    if bullets:
        raw_merges = count_merges(" ".join(bullets))
        post = _postprocess(bullets, cfg)
        post_merges = count_merges(" ".join(post))
    else:
        raw_merges = 0
        post = []
        post_merges = 0

    return {
        "sample": name,
        "model": cfg.model,
        "time_s": round(elapsed, 2),
        "raw_bullets": len(bullets or []),
        "post_bullets": len(post),
        "raw_merges": raw_merges,
        "post_merges": post_merges,
        "quality": round(score_bullets(post, expected), 2),
        "expected": expected,
        "raw_text": bullets or [],
        "post_text": post,
    }


async def main():
    parser = argparse.ArgumentParser(description="Benchmark LLM models for changelog summarization")
    default_model = Config().model
    parser.add_argument("--models", help=f"Comma-separated model names (default: {default_model})", default=default_model)
    parser.add_argument("--samples", help="Comma-separated sample names (default: all)")
    parser.add_argument("--host", default="http://localhost:11434", help="LLM API host")
    parser.add_argument("--backend", default="ollama", choices=["ollama", "openai"])
    parser.add_argument("--json", action="store_true", help="Output JSON")
    args = parser.parse_args()

    models = [m.strip() for m in args.models.split(",")]
    samples = {k: v for k, v in REFERENCE.items()
               if not args.samples or k in args.samples.split(",")}

    if not samples:
        print("No matching samples found.", file=sys.stderr)
        sys.exit(1)

    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    results = []
    for model in models:
        cfg = Config()
        cfg.model = model
        cfg.host = args.host
        cfg.backend = args.backend
        cfg.timeout = 180
        size = _model_size(model)

        print(f"\n  \033[1m{model}\033[m  ({size})  [{ts}]", file=sys.stderr)
        for sname, sample in samples.items():
            r = await run_sample(cfg, sname, sample)
            results.append(r)
            status = "\033[32mOK\033[m" if r["quality"] >= 0.6 else "\033[31mPOOR\033[m"
            merges = f" {r['post_merges']} merges" if r["post_merges"] else ""
            print(f"    {sname:<20s} {r['time_s']:>5.1f}s  {r['post_bullets']}/{r['expected']} bullets  {status}{merges}", file=sys.stderr)

    if args.json:
        print(json.dumps(results, indent=2))
        return

    # Summary table
    print(f"\n  {'Model':<25s} {'Sample':<20s} {'Time':>6s} {'Bullets':>8s} {'Quality':>8s} {'Merges':>7s}")
    print(f"  {'-'*25} {'-'*20} {'-'*6} {'-'*8} {'-'*8} {'-'*7}")
    for r in results:
        print(f"  {r['model']:<25s} {r['sample']:<20s} {r['time_s']:>5.1f}s  {r['post_bullets']}/{r['expected']:<2d}     {r['quality']:<.2f}  {r['post_merges']}")


if __name__ == "__main__":
    asyncio.run(main())
