import json
import os
import tempfile
import unittest
from reel_summarize.config import Config, load, discover_osaurus


class TestConfig(unittest.TestCase):
    def test_defaults(self):
        cfg = load("/nonexistent/path")
        self.assertEqual(cfg.host, "http://localhost:8080")
        self.assertEqual(cfg.vision_model, "qwen2.5-vl:7b")
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
        os.environ["REEL_SUMMARIZE_HOST"] = "http://other:8080"
        try:
            cfg = load("/nonexistent/path")
            self.assertEqual(cfg.host, "http://other:8080")
        finally:
            del os.environ["REEL_SUMMARIZE_HOST"]


class TestDiscoverOsaurus(unittest.TestCase):
    def test_discover_returns_none_when_no_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            # Patch the glob path to point at empty dir
            import reel_summarize.config as config_mod
            original = config_mod.OSAURUS_CONFIG_GLOB
            config_mod.OSAURUS_CONFIG_GLOB = os.path.join(tmp, "*/configuration.json")
            try:
                result = discover_osaurus()
                self.assertIsNone(result)
            finally:
                config_mod.OSAURUS_CONFIG_GLOB = original

    def test_discover_finds_running_instance(self):
        with tempfile.TemporaryDirectory() as tmp:
            instance_dir = os.path.join(tmp, "instance-abc")
            os.makedirs(instance_dir)
            config_path = os.path.join(instance_dir, "configuration.json")
            with open(config_path, "w") as f:
                json.dump({
                    "health": "running",
                    "port": 1337,
                    "address": "127.0.0.1",
                    "instanceId": "abc",
                    "updatedAt": "2026-08-02T12:00:00Z",
                }, f)

            import reel_summarize.config as config_mod
            original = config_mod.OSAURUS_CONFIG_GLOB
            config_mod.OSAURUS_CONFIG_GLOB = os.path.join(tmp, "*/configuration.json")
            try:
                result = discover_osaurus()
                self.assertEqual(result, "http://127.0.0.1:1337")
            finally:
                config_mod.OSAURUS_CONFIG_GLOB = original

    def test_discover_skips_non_running(self):
        with tempfile.TemporaryDirectory() as tmp:
            instance_dir = os.path.join(tmp, "instance-abc")
            os.makedirs(instance_dir)
            config_path = os.path.join(instance_dir, "configuration.json")
            with open(config_path, "w") as f:
                json.dump({
                    "health": "stopped",
                    "port": 1337,
                    "address": "127.0.0.1",
                }, f)

            import reel_summarize.config as config_mod
            original = config_mod.OSAURUS_CONFIG_GLOB
            config_mod.OSAURUS_CONFIG_GLOB = os.path.join(tmp, "*/configuration.json")
            try:
                result = discover_osaurus()
                self.assertIsNone(result)
            finally:
                config_mod.OSAURUS_CONFIG_GLOB = original


if __name__ == "__main__":
    unittest.main()
