#!/usr/bin/env python3
"""Fit an isotonic (PAV) calibration mapping for the Laya pre-filter.

PROVENANCE
----------
* Input pairs come from /Users/scott/laya-bench/laya100_preds.json (Laya
  predictions, ``laya_prob`` = model P(include) at the default 0.5 decision
  threshold) and /Users/scott/laya-bench/gold100.json (gold labels,
  ``gold_include``).  Both files are 192 entries over the same lines: 12 reel
  lines (5 include) + 180 AMI meeting "public" lines (36 include), labelled
  with the laya-bench line rubric (include = "carries information a summary
  should keep"; exclude = filler / disfluency / backchannel / off-topic /
  redundant restatement).
* The fit uses ALL 192 pairs (train/test split info exists in gold100.json but
  the pred file is a single snapshot from one model run; better calibration
  data would come from a held-out fold, which is noted as Phase-B work).
* ``laya_eval.py`` in laya-bench generates the preds file; regenerate it if
  the Laya checkpoint changes, then re-run this script to refresh the mapping.

METHOD
------
* Pool-Adjacent-Violators (PAV) isotonic regression, implemented in pure
  Python (no sklearn): sort by raw score, then merge adjacent blocks whose
  average label violates monotonicity, weighting each block by its size.
* Endpoints: the mapping clamps raw scores outside the observed range to the
  nearest step (no extrapolation), so boundary inputs map to the fitted edge
  values rather than inventing 0.0/1.0. Applied at runtime by
  reel_summarize/stages/laya.py's ``calibrate()``.
* Output JSON is written to reel_summarize/laya_calibration.json next to the
  package code (also copied to the repo root by default, see --output).

Usage
-----
    python3 tools/fit_laya_calibration.py            # repo default paths
    python3 tools/fit_laya_calibration.py --gold /path/gold100.json \
        --preds /path/laya100_preds.json --output /tmp/cal.json
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def pav_fit(points: list[tuple[float, int]]) -> list[tuple[float, float]]:
    """Isotonic regression via PAV; returns [(raw_score, fitted_value), ...].

    ``points`` is a list of (raw_score, binary_label) pairs.  Steps are only
    emitted where the fitted value changes, with the first step at the
    smallest raw score and the last at the largest.

    Standard PAV for isotonic regression: maintain blocks of (sum, count)
    and merge the previous block into the current one while the previous
    mean (sum/count) is strictly greater, weighting by block count.
    """
    if not points:
        return []
    by_score: dict[float, list[int]] = {}
    for raw, label in points:
        by_score.setdefault(raw, []).append(label)
    scores = sorted(by_score)
    blocks = [[scores[0], sum(by_score[scores[0]]), len(by_score[scores[0]])]]
    for s in scores[1:]:
        block = [s, sum(by_score[s]), len(by_score[s])]
        # Merge while the last block's *mean* is greater than the merged
        # mean so far (counting the current block); the merge is weighted
        # by block size so the mean of the combined block is exact.
        while (
            len(blocks) >= 1
            and blocks[-1][1] * block[2] > block[1] * blocks[-1][2]
        ):
            prev = blocks.pop()
            block = [
                block[0],
                prev[1] + block[1],
                prev[2] + block[2],
            ]
        blocks.append(block)
    out = []
    prev_val = None
    for s, total, n in blocks:
        val = total / n
        if val != prev_val:
            out.append([s, val])
            prev_val = val
    return out


def enforce_monotonic(pairs: list[list[float]]) -> list[list[float]]:
    """Clamp each value to be >= the previous one."""
    out = []
    for raw, val in pairs:
        cur = val
        if out and cur < out[-1][1]:
            cur = out[-1][1]
        out.append([raw, cur])
    return out


def fit_mapping(
    raw: list[float], labels: list[int]
) -> list[list[float]]:
    """Return [[raw_score, calibrated_p], ...] over sorted observed scores."""
    return pav_fit(list(zip(raw, labels)))


def load_pairs(preds_path: Path, gold_path: Path) -> tuple[list[float], list[int]]:
    preds = json.loads(preds_path.read_text())
    gold = json.loads(gold_path.read_text())
    gold_lines = gold["lines"]
    by_key = {(l["transcript_id"], l["line_index"]): l for l in gold_lines}
    raw, labels = [], []
    missing = 0
    for p in preds:
        g = by_key.get((p["transcript_id"], p["line_index"]))
        if g is None:
            missing += 1
            continue
        raw.append(float(p["laya_prob"]))
        labels.append(int(g["gold_include"]))
    if missing:
        print(f"warning: {missing} predictions had no matching gold line; skipped",
              file=sys.stderr)
    return raw, labels


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--preds", type=Path,
                    default=Path.home() / "laya-bench" / "laya100_preds.json")
    ap.add_argument("--gold", type=Path,
                    default=Path.home() / "laya-bench" / "gold100.json")
    ap.add_argument("--output", type=Path, default=None)
    args = ap.parse_args()

    # Default output lives inside the package so it ships with the tool.
    output = args.output or (Path(__file__).resolve().parent.parent
                             / "reel_summarize" / "laya_calibration.json")

    raw, labels = load_pairs(args.preds, args.gold)
    if len(raw) != len(labels) or not raw:
        print(f"error: need non-empty raw/label pairs, got {len(raw)}", file=sys.stderr)
        return 1

    mapping = fit_mapping(raw, labels)
    doc = {
        "schema": 1,
        "source": "laya-bench line-selection (laya100_preds.json x gold100.json)",
        "provenance": (
            "192 lines: 12 reel (5 include) + 180 AMI public (36 include); "
            "labels use the laya-bench line rubric; fit with pure-Python PAV "
            "isotonic regression; inputs outside the observed range clamp to "
            "the nearest step (no extrapolation)."
        ),
        "fit": "all 192 pairs (single pred snapshot; held-out refit = Phase B)",
        "n_pairs": len(raw),
        "base_rate": sum(labels) / len(labels),
        "apply": (
            "map raw laya_prob through these steps (linear between breakpoints) "
            "to get calibrated P(include), then keep the line iff that "
            "calibrated probability >= the configured threshold (default 0.30)."
        ),
        "mapping": mapping,
    }
    output.write_text(json.dumps(doc, indent=2) + "\n")
    print(f"wrote {output} ({output.stat().st_size} bytes)")
    print(f"fitted {len(mapping)} steps over {len(raw)} pairs")
    for raw_s, val in mapping:
        print(f"  raw {raw_s:<8.4f} -> cal {val:.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())