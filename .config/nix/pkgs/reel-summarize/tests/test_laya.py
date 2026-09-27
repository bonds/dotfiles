import unittest
from unittest.mock import patch, MagicMock

from reel_summarize.config import Config
from reel_summarize.stages.laya import filter_lines


class TestLayaFilter(unittest.TestCase):
    def _cfg(self, enabled=True, threshold=0.30, calibrated=False):
        cfg = Config()
        cfg.laya_enabled = enabled
        cfg.laya_threshold = threshold
        cfg.laya_use_calibration = calibrated
        return cfg

    def test_disabled_keeps_all(self):
        lines = ["a", "b"]
        # Even with laya uninstalled, disabled path must not touch anything.
        with patch("reel_summarize.stages.laya._laya_model", return_value=None):
            self.assertEqual(filter_lines(lines, self._cfg(enabled=False)), lines)

    @patch("reel_summarize.stages.laya._laya_model", return_value=None)
    def test_unavailable_model_keeps_all(self, _m):
        lines = ["a", "b"]
        self.assertEqual(filter_lines(lines, self._cfg()), lines)

    @patch("reel_summarize.stages.laya._load_mapping",
           return_value=[[0.0, 0.0], [0.5, 0.25], [1.0, 1.0]])
    @patch("reel_summarize.stages.laya._laya_model",
           return_value=object)  # Router factory; only predict_fn is used
    def test_calibrated_threshold(self, _m, _map):
        cfg = self._cfg(threshold=0.3, calibrated=True)
        lines = ["keep", "drop"]

        def fake_predict(line, window, router):
            # keep (raw 0.8 -> cal 0.65), drop (raw 0.4 -> cal 0.2)
            return 0.8 if line == "keep" else 0.4

        got = filter_lines(lines, cfg, predict_fn=fake_predict)
        self.assertEqual(got, ["keep"])

    def test_fallback_after_router_construction_failure(self):
        # Router() raising (e.g. model load failure) degrades to keep-all.
        cfg = self._cfg()
        lines = ["a", "b"]

        class ExplodingRouter:
            def __init__(self):
                raise RuntimeError("model load failed")

        with patch("reel_summarize.stages.laya._laya_model",
                   return_value=ExplodingRouter):
            with patch("reel_summarize.stages.laya._load_mapping",
                       return_value=[[0.0, 0.0]]):
                self.assertEqual(filter_lines(lines, cfg), lines)


if __name__ == "__main__":
    unittest.main()