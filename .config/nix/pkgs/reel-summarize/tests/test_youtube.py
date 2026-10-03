import json
import os
import tempfile
import unittest
from unittest.mock import patch, MagicMock

from reel_summarize.config import Config
from reel_summarize.errors import DownloadError
from reel_summarize.stages.youtube import (
    is_youtube_url,
    download_audio,
    fetch_captions,
    _parse_vtt,
    _parse_json3,
)
from reel_summarize.stages.summarize import split_text, generate_summary_chunked


class TestIsYoutubeUrl(unittest.TestCase):
    def test_non_string_is_not_youtube(self):
        self.assertFalse(is_youtube_url(None))
        self.assertFalse(is_youtube_url(123))

    def test_youtube_hosts(self):
        for url in [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtube.com/watch?v=abc",
            "https://m.youtube.com/watch?v=abc",
            "https://music.youtube.com/watch?v=abc",
            "https://youtu.be/dQw4w9WgXcQ",
            "https://www.youtube-nocookie.com/embed/abc",
            "https://music.youtube.com/playlist?list=PLx",
        ]:
            self.assertTrue(is_youtube_url(url), url)

    def test_non_youtube(self):
        for url in [
            "https://instagram.com/reel/xyz",
            "https://notyoutube.com/watch?v=abc",
            "https://evil-youtube.com.evil.example/watch?v=abc",
            "https://example.com/youtube/watch?v=abc",
            "https://youtu.be.evil.example/abc",
            "not a url",
            "",
        ]:
            self.assertFalse(is_youtube_url(url), url)


class TestVttParser(unittest.TestCase):
    def test_parse_vtt_dedupes_rolling_cues(self):
        vtt = """WEBVTT

00:00:00.000 --> 00:00:02.000
hello world

00:00:02.000 --> 00:00:04.000
hello world
again

00:00:04.000 --> 00:00:06.000
more text
"""
        segs = _parse_vtt(vtt)
        self.assertEqual(len(segs), 3)
        self.assertEqual(segs[0]["text"], "hello world")
        self.assertEqual(segs[1]["text"], "again")  # rolling repeat dropped
        self.assertEqual(segs[2]["start"], 4.0)
        self.assertEqual(segs[2]["end"], 6.0)

    def test_parse_vtt_strips_tags(self):
        vtt = "00:00:00.000 --> 00:00:01.000\n<c>hi</c> <00:00:00.500>there\n"
        segs = _parse_vtt(vtt)
        self.assertEqual(segs[0]["text"], "hi there")


class TestJson3Parser(unittest.TestCase):
    def test_parse_json3(self):
        data = {
            "events": [
                {"tStartMs": 0, "segs": [{"utf8": "one "}, {"utf8": "two"}]},
                {"tStartMs": 2500, "segs": [{"utf8": "three"}]},
                {"tStartMs": 5000},  # no segs → skipped
            ]
        }
        segs = _parse_json3(json.dumps(data))
        self.assertEqual(len(segs), 2)
        self.assertEqual(segs[0]["text"], "one two")
        self.assertEqual(segs[0]["start"], 0.0)
        self.assertEqual(segs[1]["start"], 2.5)


class TestDownloadAudio(unittest.TestCase):
    @patch("reel_summarize.stages.youtube.subprocess.run")
    def test_success_returns_produced_file(self, mock_run):
        mock_run.return_value.returncode = 0
        mock_run.return_value.stdout = ""
        with tempfile.TemporaryDirectory() as tmp:
            fake = os.path.join(tmp, "audio_src.m4a")
            open(fake, "w").close()

            def _run(cmd, **kwargs):
                return MagicMock(returncode=0, stdout="", stderr="")

            mock_run.side_effect = _run
            path = download_audio("https://youtu.be/abc", tmp)
            self.assertEqual(path, fake)

    @patch("reel_summarize.stages.youtube.subprocess.run")
    def test_failure_raises_download_error(self, mock_run):
        mock_run.return_value.returncode = 1
        mock_run.return_value.stderr = "HTTP Error 403"
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(DownloadError):
                download_audio("https://youtu.be/abc", tmp)


class TestFetchCaptions(unittest.TestCase):
    @patch("reel_summarize.stages.youtube.subprocess.run")
    @patch("reel_summarize.stages.youtube.time.sleep")
    def test_429_retries_then_falls_back(self, mock_sleep, mock_run):
        """HTTP 429 twice (with backoff), then no file → None (whisper fallback)."""
        rate = MagicMock(returncode=1, stderr="HTTP Error 429: Too Many Requests", stdout="")
        mock_run.return_value = rate
        with tempfile.TemporaryDirectory() as tmp:
            result = fetch_captions("https://youtu.be/abc", tmp, retries=2)
            self.assertIsNone(result)  # never fatal — caller falls back to whisper
            self.assertEqual(mock_run.call_count, 3)  # initial + 2 retries
            self.assertEqual(mock_sleep.call_count, 2)
            mock_sleep.assert_any_call(5)
            mock_sleep.assert_any_call(15)

    @patch("reel_summarize.stages.youtube.subprocess.run")
    @patch("reel_summarize.stages.youtube.time.sleep")
    def test_429_twice_then_success(self, mock_sleep, mock_run):
        rate = MagicMock(returncode=1, stderr="HTTP Error 429", stdout="")
        ok = MagicMock(returncode=0, stdout="", stderr="")

        def _run(cmd, **kwargs):
            return ok

        mock_run.side_effect = [rate, rate, ok]
        with tempfile.TemporaryDirectory() as tmp:
            with open(os.path.join(tmp, "caps.en.vtt"), "w") as f:
                f.write("00:00:00.000 --> 00:00:01.000\ncaption line\n")
            segs = fetch_captions("https://youtu.be/abc", tmp, retries=2)
            self.assertIsNotNone(segs)
            self.assertEqual(segs[0]["text"], "caption line")
            self.assertEqual(mock_sleep.call_count, 2)

    @patch("reel_summarize.stages.youtube.subprocess.run")
    @patch("reel_summarize.stages.youtube.time.sleep")
    def test_hard_failure_returns_none_no_retry(self, mock_sleep, mock_run):
        mock_run.return_value = MagicMock(
            returncode=1, stderr="ERROR: no subtitles", stdout=""
        )
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIsNone(fetch_captions("https://youtu.be/abc", tmp, retries=2))
            self.assertEqual(mock_run.call_count, 1)  # non-429: no retry
            mock_sleep.assert_not_called()

    @patch("reel_summarize.stages.youtube.subprocess.run")
    @patch("reel_summarize.stages.youtube.time.sleep")
    def test_hard_failure_with_written_file_still_returns_segments(self, mock_sleep, mock_run):
        """yt-dlp may exit non-zero yet leave a usable subtitle file — use it."""
        mock_run.return_value = MagicMock(
            returncode=1, stderr="WARNING: something", stdout=""
        )
        with tempfile.TemporaryDirectory() as tmp:
            with open(os.path.join(tmp, "caps.en.json3"), "w") as f:
                json.dump({"events": [
                    {"tStartMs": 0, "segs": [{"utf8": "partial line"}]},
                ]}, f)
            segs = fetch_captions("https://youtu.be/abc", tmp, retries=2)
            self.assertIsNotNone(segs)
            self.assertEqual(segs[0]["text"], "partial line")

    @patch("reel_summarize.stages.youtube.subprocess.run")
    @patch("reel_summarize.stages.youtube.time.sleep")
    def test_no_captions_available_returns_none(self, mock_sleep, mock_run):
        mock_run.return_value = MagicMock(returncode=0, stdout="", stderr="")
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIsNone(fetch_captions("https://youtu.be/abc", tmp))
            mock_sleep.assert_not_called()


class TestSplitText(unittest.TestCase):
    def test_short_text_single_chunk(self):
        self.assertEqual(split_text("hello", 100, 10), ["hello"])

    def test_chunks_respect_limit_and_overlap(self):
        # sentences of ~11 chars each
        text = " ".join(f"sentence{i:03d}." for i in range(500))  # ~6000 chars
        chunks = split_text(text, 1000, 100)
        self.assertGreater(len(chunks), 1)
        for c in chunks:
            self.assertLessEqual(len(c), 1000)
        # consecutive chunks overlap: the seam region appears in both
        for a, b in zip(chunks, chunks[1:]):
            seam = b[: min(60, len(b))]
            self.assertIn(seam.rstrip(), a)
        # no text lost: first chunk starts at the beginning, last ends at end
        self.assertTrue(chunks[0].startswith("sentence000"))
        self.assertTrue(chunks[-1].rstrip().endswith("."))
        # full reassembly covers everything (with overlap, join must contain all sentences)
        joined = "".join(chunks)
        for i in (0, 499):
            self.assertIn(f"sentence{i:03d}.", joined)

    def test_no_infinite_loop_on_unbroken_text(self):
        text = "x" * 5000  # no sentence boundaries at all
        chunks = split_text(text, 1000, 100)
        self.assertGreaterEqual(len(chunks), 5)
        for c in chunks:
            self.assertLessEqual(len(c), 1000)


class TestGenerateSummaryChunked(unittest.TestCase):
    @patch("reel_summarize.stages.summarize._dispatch")
    def test_under_limit_is_single_shot(self, mock_dispatch):
        mock_dispatch.return_value = "final"
        cfg = Config(summary_max_chars=100)
        out = generate_summary_chunked(
            transcript="short", vision_timeline="", caption="c",
            author="a", cfg=cfg, platform="youtube",
        )
        self.assertEqual(out, "final")
        mock_dispatch.assert_called_once()

    @patch("reel_summarize.stages.summarize._dispatch")
    def test_over_limit_maps_then_reduces(self, mock_dispatch):
        calls = {"n": 0}

        def _side_effect(*a, **k):
            calls["n"] += 1
            return f"part{calls['n']}"

        mock_dispatch.side_effect = _side_effect
        cfg = Config(
            summary_max_chars=1000,
            mapreduce_chunk_chars=600,
            mapreduce_overlap_chars=50,
        )
        transcript = " ".join(f"sentence{i:04d}." for i in range(400))  # ~5600 chars
        out = generate_summary_chunked(
            transcript=transcript, vision_timeline="", caption="The Video",
            author="chan", cfg=cfg, platform="youtube",
        )
        n_calls = mock_dispatch.call_count
        self.assertGreater(n_calls, 2)          # >1 map + 1 reduce
        # final call is the reduce prompt and carries the partial summaries
        final_prompt = mock_dispatch.call_args_list[-1].args[0]
        self.assertIn("Partial summaries", final_prompt)
        self.assertIn("The Video", final_prompt)
        self.assertTrue(out)


if __name__ == "__main__":
    unittest.main()
