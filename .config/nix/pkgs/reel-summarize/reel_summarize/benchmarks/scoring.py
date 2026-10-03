"""Benchmark metrics for reel-summarize backends."""

from __future__ import annotations

import re
import time
from dataclasses import dataclass, field


@dataclass
class VisionMetrics:
    total_time_s: float = 0.0
    per_frame_s: list[float] = field(default_factory=list)
    json_ok: int = 0
    json_fail: int = 0
    errors: int = 0

    @property
    def frame_count(self) -> int:
        return len(self.per_frame_s)

    @property
    def avg_per_frame_s(self) -> float:
        if not self.per_frame_s:
            return 0.0
        return sum(self.per_frame_s) / len(self.per_frame_s)

    @property
    def json_ok_rate(self) -> str:
        total = self.json_ok + self.json_fail
        if total == 0:
            return "n/a"
        return f"{self.json_ok}/{total}"


@dataclass
class SummaryMetrics:
    time_s: float = 0.0
    word_count: int = 0
    error: bool = False


@dataclass
class BenchmarkResult:
    backend: str
    model: str
    sample: str
    vision: VisionMetrics = field(default_factory=VisionMetrics)
    summary: SummaryMetrics = field(default_factory=SummaryMetrics)
    output_text: str = ""

    @property
    def total_time_s(self) -> float:
        return self.vision.total_time_s + self.summary.time_s


class Timer:
    """Context manager that records elapsed time."""

    def __init__(self):
        self.start: float = 0.0
        self.elapsed: float = 0.0

    def __enter__(self):
        self.start = time.monotonic()
        return self

    def __exit__(self, *_):
        self.elapsed = time.monotonic() - self.start


def word_count(text: str) -> int:
    return len(text.split())


def count_word_merges(text: str) -> int:
    """Count doubled first letters (ssystemd, iinto) — same heuristic as what-changed."""
    return len(re.findall(r"\b(\w)\1(\w{2,})\b", text))
