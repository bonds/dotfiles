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
        mock_httpx.TimeoutException = type("TimeoutException", (Exception,), {})
        mock_httpx.RequestError = type("RequestError", (Exception,), {})
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
        mock_httpx.TimeoutException = type("TimeoutException", (Exception,), {})
        mock_httpx.RequestError = type("RequestError", (Exception,), {})
        cfg = Config()
        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as f:
            f.write(b"fake")
            f.flush()
        with patch.dict('sys.modules', {'httpx': mock_httpx}):
            results = analyze_frames([f.name], cfg)
        self.assertIn("raw text output", results[0]["text"])


class TestVisionOsaurus(unittest.TestCase):
    def test_osaurus_vision_call(self):
        mock_httpx = MagicMock()
        mock_response = MagicMock()
        mock_response.json.return_value = {
            "choices": [{"message": {"content": '{"text": ["Osaurus text"], "scene": "Osaurus scene"}'}}]
        }
        mock_response.raise_for_status.return_value = None
        mock_httpx.post.return_value = mock_response

        cfg = Config(backend="osaurus", host="http://127.0.0.1:1337")
        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as f:
            f.write(b"fake image data")
            f.flush()
            frames = [f.name]
        with patch.dict('sys.modules', {'httpx': mock_httpx}):
            results = analyze_frames(frames, cfg)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["text"], ["Osaurus text"])
        self.assertEqual(results[0]["scene"], "Osaurus scene")

        # Verify it hit the /v1/chat/completions endpoint
        call_args = mock_httpx.post.call_args
        self.assertIn("/v1/chat/completions", call_args[0][0])

    def test_osaurus_vision_uses_cfg_host(self):
        mock_httpx = MagicMock()
        mock_response = MagicMock()
        mock_response.json.return_value = {
            "choices": [{"message": {"content": '{"text": [], "scene": ""}'}}]
        }
        mock_response.raise_for_status.return_value = None
        mock_httpx.post.return_value = mock_response

        cfg = Config(backend="osaurus", host="http://192.168.1.50:1337")
        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as f:
            f.write(b"fake")
            f.flush()
        with patch.dict('sys.modules', {'httpx': mock_httpx}):
            analyze_frames([f.name], cfg)

        call_args = mock_httpx.post.call_args
        self.assertTrue(call_args[0][0].startswith("http://192.168.1.50:1337"))


class TestVisionTimeline(unittest.TestCase):
    def test_format_timeline(self):
        frames = ["f1.jpg", "f2.jpg"]
        results = [
            {"text": ["Hello"], "scene": "person talking", "objects": [{"name": "microphone", "detail": "on a stand"}]},
            {"text": ["Buy now"], "scene": "product shown", "objects": []},
        ]
        timeline = format_vision_timeline(frames, results, fps=1)
        self.assertIn("[t=0s]", timeline)
        self.assertIn("Hello", timeline)
        self.assertIn("microphone: on a stand", timeline)
        self.assertIn("[t=1s]", timeline)
        self.assertIn("Buy now", timeline)

    def test_objects_normalization(self):
        # Flat-string objects and a missing objects key both normalize safely.
        from reel_summarize.stages.vision import _normalize_vision
        res = _normalize_vision({"text": ["Buy now"], "scene": "shop", "objects": ["camera", "clock"]})
        self.assertEqual(
            res["objects"],
            [{"name": "camera", "detail": ""}, {"name": "clock", "detail": ""}],
        )
        res2 = _normalize_vision({"text": ["x"], "scene": "y"})
        self.assertEqual(res2["objects"], [])
        res3 = _normalize_vision("raw text fallback")
        self.assertEqual(res3["text"], ["raw text fallback"])
        self.assertEqual(res3["objects"], [])
