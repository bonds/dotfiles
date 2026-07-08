import sys
import unittest
from unittest.mock import MagicMock, patch
from reel_summarize.config import Config
from reel_summarize.stages.summarize import generate_summary


class TestSummarize(unittest.TestCase):
    def test_generate_summary(self):
        mock_httpx = MagicMock()
        mock_response = MagicMock()
        mock_response.json.return_value = {"response": "This reel is about cats."}
        mock_response.raise_for_status.return_value = None
        mock_httpx.post.return_value = mock_response

        cfg = Config()
        with patch.dict('sys.modules', {'httpx': mock_httpx}):
            result = generate_summary(
                transcript="cats are great",
                vision_timeline="[t=0s] scene: cat; text: ['meow']",
                caption="Cute cat video",
                author="catlover",
                cfg=cfg,
            )
        self.assertEqual(result, "This reel is about cats.")
        call_args = mock_httpx.post.call_args
        self.assertIsNotNone(call_args)
        payload = call_args[1]["json"]
        self.assertIn("catlover", payload["prompt"])
        self.assertIn("Cute cat video", payload["prompt"])
        self.assertIn("cats are great", payload["prompt"])
