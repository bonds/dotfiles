import sys
import unittest
from unittest.mock import MagicMock, patch
from reel_summarize.config import Config
from reel_summarize.errors import SummaryError
from reel_summarize.stages.summarize import generate_summary


class TestSummarize(unittest.TestCase):
    def test_generate_summary(self):
        mock_httpx = MagicMock()
        mock_response = MagicMock()
        mock_response.json.return_value = {"response": "This reel is about cats."}
        mock_response.raise_for_status.return_value = None
        mock_httpx.post.return_value = mock_response
        mock_httpx.TimeoutException = type("TimeoutException", (Exception,), {})
        mock_httpx.RequestError = type("RequestError", (Exception,), {})

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


class TestSummarizeOsaurus(unittest.TestCase):
    def test_osaurus_summary_call(self):
        mock_httpx = MagicMock()
        mock_response = MagicMock()
        mock_response.json.return_value = {
            "choices": [{"message": {"content": "This reel is about Osaurus."}}]
        }
        mock_response.raise_for_status.return_value = None
        mock_httpx.post.return_value = mock_response

        cfg = Config(backend="osaurus", host="http://127.0.0.1:1337")
        with patch.dict('sys.modules', {'httpx': mock_httpx}):
            result = generate_summary(
                transcript="local AI models",
                vision_timeline="[t=0s] scene: tech demo",
                caption="Osaurus demo",
                author="osaurus_ai",
                cfg=cfg,
            )
        self.assertEqual(result, "This reel is about Osaurus.")
        call_args = mock_httpx.post.call_args
        self.assertIn("/v1/chat/completions", call_args[0][0])
        payload = call_args[1]["json"]
        self.assertIn("osaurus_ai", payload["messages"][0]["content"])

    def test_osaurus_uses_cfg_host(self):
        mock_httpx = MagicMock()
        mock_response = MagicMock()
        mock_response.json.return_value = {
            "choices": [{"message": {"content": "ok"}}]
        }
        mock_response.raise_for_status.return_value = None
        mock_httpx.post.return_value = mock_response

        cfg = Config(backend="osaurus", host="http://192.168.1.50:1337")
        with patch.dict('sys.modules', {'httpx': mock_httpx}):
            generate_summary(
                transcript="test",
                vision_timeline="",
                caption=None,
                author=None,
                cfg=cfg,
            )
        call_args = mock_httpx.post.call_args
        self.assertTrue(call_args[0][0].startswith("http://192.168.1.50:1337"))


class TestSummaryErrorOnFailure(unittest.TestCase):
    """Verify that LLM failures raise SummaryError, not sys.exit / SystemExit."""

    def _make_request_error(self, msg="connection refused"):
        """Create a mock httpx.RequestError subclass."""
        return type("RequestError", (Exception,), {"__init__": lambda self, m=msg: setattr(self, "msg", m)})

    def test_ollama_unreachable_raises_summary_error(self):
        mock_httpx = MagicMock()
        RequestError = self._make_request_error()
        mock_httpx.RequestError = RequestError
        mock_httpx.post.side_effect = RequestError("connection refused")

        cfg = Config()
        with patch.dict("sys.modules", {"httpx": mock_httpx}):
            with self.assertRaises(SummaryError) as ctx:
                generate_summary(
                    transcript="test",
                    vision_timeline="",
                    caption=None,
                    author=None,
                    cfg=cfg,
                )
            self.assertIn("cannot reach LLM", str(ctx.exception))

    def test_openai_unreachable_raises_summary_error(self):
        mock_httpx = MagicMock()
        RequestError = self._make_request_error()
        mock_httpx.RequestError = RequestError
        mock_httpx.post.side_effect = RequestError("timeout")

        cfg = Config(backend="openai", host="http://10.0.0.1:8080")
        with patch.dict("sys.modules", {"httpx": mock_httpx}):
            with self.assertRaises(SummaryError) as ctx:
                generate_summary(
                    transcript="test",
                    vision_timeline="",
                    caption=None,
                    author=None,
                    cfg=cfg,
                )
            self.assertIn("cannot reach LLM", str(ctx.exception))

    def test_osaurus_unreachable_raises_summary_error(self):
        mock_httpx = MagicMock()
        RequestError = self._make_request_error()
        mock_httpx.RequestError = RequestError
        # First call is GET /v1/models (for auto-detect), second is POST
        mock_httpx.get.side_effect = RequestError("connection refused")
        mock_httpx.post.side_effect = RequestError("connection refused")

        cfg = Config(backend="osaurus", host="http://10.0.0.1:1337")
        with patch.dict("sys.modules", {"httpx": mock_httpx}):
            with self.assertRaises(SummaryError) as ctx:
                generate_summary(
                    transcript="test",
                    vision_timeline="",
                    caption=None,
                    author=None,
                    cfg=cfg,
                )
            self.assertIn("cannot reach Osaurus", str(ctx.exception))

    def test_no_system_exit_on_failure(self):
        """The original bug: sys.exit(2) killed the MCP server process."""
        mock_httpx = MagicMock()
        RequestError = self._make_request_error()
        mock_httpx.RequestError = RequestError
        mock_httpx.post.side_effect = RequestError("down")

        cfg = Config()
        with patch.dict("sys.modules", {"httpx": mock_httpx}):
            try:
                generate_summary(
                    transcript="test", vision_timeline="", caption=None, author=None, cfg=cfg
                )
                self.fail("Expected SummaryError")
            except SummaryError:
                pass  # correct
            except SystemExit:
                self.fail("Got SystemExit instead of SummaryError — server would crash!")
