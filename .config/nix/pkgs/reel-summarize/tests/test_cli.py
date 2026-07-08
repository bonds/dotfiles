import unittest
from unittest.mock import patch
from reel_summarize.cli import entry


class TestCLI(unittest.TestCase):
    @patch("reel_summarize.cli._preflight")
    def test_preflight_flag(self, mock_preflight):
        with patch("sys.argv", ["reel-summarize", "--preflight"]):
            with self.assertRaises(SystemExit):
                entry()

    @patch("reel_summarize.cli.run")
    def test_run_with_url(self, mock_run):
        with patch("sys.argv", ["reel-summarize", "https://instagram.com/reel/xyz"]):
            entry()
            mock_run.assert_called_once()

    @patch("reel_summarize.cli.run")
    def test_keep_artifacts_flag(self, mock_run):
        with patch("sys.argv", ["reel-summarize", "https://instagram.com/reel/xyz", "--keep-artifacts"]):
            entry()
            args, kwargs = mock_run.call_args
            self.assertTrue(kwargs["keep_artifacts"])
