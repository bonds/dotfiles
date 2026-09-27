"""Laya pre-filter stage: decide which transcript lines reach the summarizer.

SEMANTICS / THRESHOLD DECISION
------------------------------
The layer sits between transcription and summarization.  Whisper returns
segments; transcribe_text() currently joins them into one blob for the single
summarizer prompt.  Laya judges each transcript LINE (one per whisper segment)
with the same include-question used by laya-bench/laya_eval.py: a noul
question over {false: no, true: yes} where ``laya_prob`` = P(include) =
1 - noul.

Calibration reality (see reel_summarize/laya_calibration.json, fit by
tools/fit_laya_calibration.py on the 192 laya-bench pairs): the PAV mapping is
monotone but WEAK — the highest observed calibrated P(include) is ~0.33 while
the base rate is 0.21.  So interpreting ``laya_threshold`` on the CALIBRATED
scale nearly always rejects everything once the threshold is above the base
rate.

Decision (honest reading of the data):
  * ``cfg.laya_threshold`` (default 0.30) is a RAW-score threshold.  This is
    the operating point the model was validated at (laya_eval.py derives
    laya_include = laya_prob >= 0.5, and 0.30 was the chosen reject point
    during laya-bench tuning).
  * ``cfg.laya_use_calibration`` (default False) switches the threshold to the
    CALIBRATED P(include) scale for a target-recall mode.  With the current
    fit, a calibrated threshold above ~0.33 keeps nothing; users asking for
    calibration should set it with that in mind.

Either way the stage only REMOVES low-scoring lines; on any failure (model,
calibration file, unexpected shape) it degrades to "keep everything" so the
existing summarizer path is unchanged.
"""
from __future__ import annotations

import json
import os
import sys
from functools import lru_cache

from reel_summarize.config import Config

# Layered laya availability: a venv created by the packaging layer (systemd
# ExecStartPre, see pkgs/reel-summarize-mcp + hosts/sophrosyne/configuration.nix)
# may be the only place laya + torch live.  If present, its site-packages is
# appended to sys.path so the normal ``import laya`` below resolves.
LAYA_VENV_SITE = os.environ.get("LAYA_VENV_SITE") or os.path.expanduser(
    "/var/lib/reel-summarize-mcp/laya-venv/lib/python*/site-packages")


def _venv_site_packages() -> str | None:
    import glob

    matches = glob.glob(LAYA_VENV_SITE)
    return matches[0] if matches else None


_venv_added = False


def _add_venv_to_path() -> None:
    global _venv_added
    if _venv_added:
        return
    site = _venv_site_packages()
    if site and site not in sys.path:
        sys.path.insert(0, site)
    _venv_added = True


# Same question laya-bench/laya_eval.py uses.  ``noul`` = P(option 1); the
# criteria dict is rendered in key order, so option 1 is "no": noul = P(no)
# and P(include) = 1 - noul.
_INCLUDE_QUESTION = {
    "include": {
        "type": "noul",
        "instructions": (
            "A recap of a social-media video reel is being written as a short "
            "prose summary. One line of the spoken transcript is shown, plus "
            "the surrounding context. Decide whether that line should be "
            "included in the summary. Answer 'no' if the line is filler, "
            "off-topic, or redundant with nearby lines; answer 'yes' only if "
            "it carries information the summary should keep."
        ),
    }
}


def _calibration_path() -> str:
    return os.path.join(os.path.dirname(os.path.dirname(__file__)), "laya_calibration.json")


@lru_cache(maxsize=1)
def _load_mapping() -> list[list[float]]:
    """Load [[raw, cal], ...] from the calibration artifact (cached)."""
    path = _calibration_path()
    with open(path) as f:
        doc = json.load(f)
    return [list(map(float, step)) for step in doc["mapping"]]


def _extract_include(answers: dict) -> float:
    """Pull P(include) from a Laya noul answer dict."""
    include = answers.get("include", {})
    noul = float(include.get("noul", 1.0))
    return 1.0 - noul


def _pav_lookup(raw: float, mapping: list[list[float]]) -> float:
    """Map a raw score through the piecewise-linear PAV schedule.

    Raw scores outside the observed range clamp to the nearest step (no
    extrapolation), as documented by the calibration artifact.
    """
    if raw <= mapping[0][0]:
        return mapping[0][1]
    if raw >= mapping[-1][0]:
        return mapping[-1][1]
    for (r0, c0), (r1, c1) in zip(mapping, mapping[1:]):
        if r0 <= raw <= r1:
            if r1 == r0:
                return c1
            return c0 + (c1 - c0) * (raw - r0) / (r1 - r0)
    return mapping[-1][1]


_WARNED = set()


def _warn_once(msg: str) -> None:
    if msg not in _WARNED:
        import sys

        print(f"  ⚠ laya: {msg}", file=sys.stderr, flush=True)
        _WARNED.add(msg)


def _laya_model():
    """Import Laya lazily; returns the Router factory or None if unavailable."""
    try:
        _add_venv_to_path()
        from laya import Router

        return Router
    except ImportError as e:
        _warn_once(f"laya import failed ({e}); keeping every line")
        return None


def filter_lines(
    lines: list[str],
    cfg: Config,
    state_text_fn=None,
    predict_fn=None,
) -> list[str]:
    """Decide which transcript lines keep going to the summarizer.

    Each line is scored by the Laya English checkpoint against the include
    question (with the line plus surrounding context), the raw probability is
    optionally calibrated, then thresholded.  Any failure returns all lines
    unchanged.

    ``state_text_fn`` / ``predict_fn`` exist for injection in tests; defaults
    mirror laya_eval.py's state layout and batched prediction.
    """
    if not cfg.laya_enabled:
        return lines
    if not lines:
        return lines

    Router = _laya_model()
    if Router is None:
        return lines

    try:
        mapping = _load_mapping()
    except Exception as e:
        _warn_once(f"calibration load failed ({e}); keeping every line")
        return lines

    try:
        router = Router()
        context_lines = list(lines)
        states = []
        for i, line in enumerate(lines):
            # Surrounding context: up to 3 lines on either side.
            window_start = max(0, i - 3)
            window_end = min(len(context_lines), i + 4)
            window = " ".join(context_lines[window_start:window_end])
            states.append((line, window))

        if predict_fn is not None:
            results = [
                predict_fn(line, window, router)
                for line, window in states
            ]
        else:
            question = _INCLUDE_QUESTION
            results = router.predict_batch(
                [
                    {
                        "state": state_text_fn(line, window) if state_text_fn else
                        f"Transcript line: {line}\nContext: {window}",
                        "questions": question,
                        "model": "english",
                    }
                    for line, window in states
                ],
                batch_size=min(64, max(1, len(states))),
            )

        kept = []
        dropped = 0
        for i, line in enumerate(lines):
            try:
                if predict_fn is not None:
                    p_inc = float(results[i])
                else:
                    p_inc = _extract_include(results[i]["answers"])
            except (KeyError, TypeError, IndexError, ValueError) as e:
                _warn_once(f"unparseable prediction #{i} ({e}); keeping line")
                kept.append(line)
                continue

            if cfg.laya_use_calibration:
                score = _pav_lookup(p_inc, mapping)
            else:
                score = p_inc

            if score >= cfg.laya_threshold:
                kept.append(line)
            else:
                dropped += 1

        if dropped:
            _warn_once(
                f"filtered {dropped}/{len(lines)} low-salience lines "
                f"(threshold={cfg.laya_threshold}"
                f"{' calibrated' if cfg.laya_use_calibration else ' raw'})"
            )
        return kept
    except Exception as e:
        _warn_once(f"filter failed ({e}); keeping every line")
        return lines