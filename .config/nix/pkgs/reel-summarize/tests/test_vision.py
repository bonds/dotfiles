import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch
from reel_summarize.config import Config
from reel_summarize.stages.vision import analyze_frames, format_vision_timeline


class TestVisionOllama(unittest.TestCase):
    def _make_mock_httpx(self):
        mock_httpx = MagicMock()
        mock_response = MagicMock()
        mock_response.json.return_value = {"response": '{"text": ["Hello"], "scene": "a person talking"}'}
        mock_response.raise_for_status.return_value = None
        mock_httpx.post.return_value = mock_response
        return mock_httpx

    def test_vision_call(self):
        mock_httpx = self._make_mock_httpx()
        cfg = Config()
        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as f:
            f.write(b"fake image data")
            f.flush()
            frames = [f.name]
        with patch.dict('sys.modules', {'httpx': mock_httpx}):
            results = analyze_frames(frames, cfg)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["text"], ["Hello"])
        self.assertEqual(results[0]["scene"], "a person talking")

    def test_vision_fallback_on_bad_json(self):
        mock_httpx = MagicMock()
        mock_response = MagicMock()
        mock_response.json.return_value = {"response": "raw text output"}
        mock_response.raise_for_status.return_value = None
        mock_httpx.post.return_value = mock_response
        cfg = Config()
        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as f:
            f.write(b"fake")
            f.flush()
        with patch.dict('sys.modules', {'httpx': mock_httpx}):
            results = analyze_frames([f.name], cfg)
        self.assertIn("raw text output", results[0]["text"])


class TestVisionTimeline(unittest.TestCase):
    def test_format_timeline(self):
        frames = ["f1.jpg", "f2.jpg"]
        results = [
            {"text": ["Hello"], "scene": "person talking"},
            {"text": ["Buy now"], "scene": "product shown"},
        ]
        timeline = format_vision_timeline(frames, results, fps=1)
        self.assertIn("[t=0s]", timeline)
        self.assertIn("Hello", timeline)
        self.assertIn("[t=1s]", timeline)
        self.assertIn("Buy now", timeline)
