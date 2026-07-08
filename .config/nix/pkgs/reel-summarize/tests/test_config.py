import os
import tempfile
import unittest
from reel_summarize.config import Config, load


class TestConfig(unittest.TestCase):
    def test_defaults(self):
        cfg = load("/nonexistent/path")
        self.assertEqual(cfg.host, "http://localhost:11434")
        self.assertEqual(cfg.vision_model, "qwen2-vl:7b")
        self.assertEqual(cfg.frames_per_second, 1)

    def test_toml_overrides(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".toml", delete=False) as f:
            f.write('frames_per_second = 2\n')
            f.write('max_frames = 10\n')
            path = f.name
        try:
            cfg = load(path)
            self.assertEqual(cfg.frames_per_second, 2)
            self.assertEqual(cfg.max_frames, 10)
        finally:
            os.unlink(path)

    def test_env_overrides(self):
        os.environ["REEL_SUMMARIZE_OLLAMA_HOST"] = "http://other:11434"
        try:
            cfg = load("/nonexistent/path")
            self.assertEqual(cfg.host, "http://other:11434")
        finally:
            del os.environ["REEL_SUMMARIZE_OLLAMA_HOST"]
