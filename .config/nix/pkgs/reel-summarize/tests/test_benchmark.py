import json
import os
import tempfile
import unittest
from unittest.mock import patch, MagicMock

from reel_summarize.benchmarks.scoring import (
    BenchmarkResult,
    SummaryMetrics,
    Timer,
    VisionMetrics,
    count_word_merges,
    word_count,
)
from reel_summarize.benchmarks.runner import (
    _load_sample_defs,
    _load_sample_frames,
    _load_sample_metadata,
    _load_sample_transcript,
    print_table,
)


class TestScoring(unittest.TestCase):
    def test_word_count(self):
        self.assertEqual(word_count("hello world"), 2)
        self.assertEqual(word_count(""), 0)
        self.assertEqual(word_count("one"), 1)

    def test_count_word_merges(self):
        self.assertEqual(count_word_merges("ssystemd is great"), 1)
        self.assertEqual(count_word_merges("iinto the void"), 1)
        self.assertEqual(count_word_merges("no merges here"), 0)

    def test_vision_metrics(self):
        vm = VisionMetrics(total_time_s=10.0, per_frame_s=[1.0, 2.0, 3.0], json_ok=2, json_fail=1)
        self.assertEqual(vm.frame_count, 3)
        self.assertAlmostEqual(vm.avg_per_frame_s, 2.0)
        self.assertEqual(vm.json_ok_rate, "2/3")

    def test_vision_metrics_empty(self):
        vm = VisionMetrics()
        self.assertEqual(vm.frame_count, 0)
        self.assertEqual(vm.avg_per_frame_s, 0.0)
        self.assertEqual(vm.json_ok_rate, "n/a")

    def test_summary_metrics(self):
        sm = SummaryMetrics(time_s=2.5, word_count=42)
        self.assertEqual(sm.time_s, 2.5)
        self.assertFalse(sm.error)

    def test_benchmark_result_total_time(self):
        br = BenchmarkResult(
            backend="osaurus",
            model="test",
            sample="reel-001",
            vision=VisionMetrics(total_time_s=8.0),
            summary=SummaryMetrics(time_s=2.0),
        )
        self.assertEqual(br.total_time_s, 10.0)

    def test_timer(self):
        with Timer() as t:
            pass
        self.assertGreater(t.elapsed, 0)


class TestSampleLoading(unittest.TestCase):
    def test_load_sample_defs(self):
        defs = _load_sample_defs()
        self.assertIn("reel-001", defs)
        self.assertEqual(defs["reel-001"]["url"], "https://www.instagram.com/reel/DYVuhyRyroo/")

    def test_load_sample_frames(self):
        frames = _load_sample_frames("reel-001")
        self.assertGreater(len(frames), 0)
        self.assertTrue(all(f.endswith(".jpg") for f in frames))

    def test_load_sample_metadata(self):
        meta = _load_sample_metadata("reel-001")
        self.assertIn("author", meta)

    def test_load_sample_transcript(self):
        transcript = _load_sample_transcript("reel-001")
        self.assertIsInstance(transcript, str)

    def test_load_nonexistent_sample(self):
        frames = _load_sample_frames("nonexistent")
        self.assertEqual(frames, [])


class TestPrintTable(unittest.TestCase):
    def test_print_table(self):
        results = [
            BenchmarkResult(
                backend="osaurus",
                model="qwen2.5-vl:7b",
                sample="reel-001",
                vision=VisionMetrics(total_time_s=8.5, per_frame_s=[0.85] * 10, json_ok=10, json_fail=0),
                summary=SummaryMetrics(time_s=1.2, word_count=87),
                output_text="Test summary output.",
            ),
        ]
        # Just verify it doesn't crash
        print_table(results)


if __name__ == "__main__":
    unittest.main()
