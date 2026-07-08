import unittest
from unittest.mock import patch, MagicMock
from reel_summarize.config import Config
from reel_summarize.pipeline import run


class TestPipeline(unittest.TestCase):
    @patch("reel_summarize.pipeline.download")
    @patch("reel_summarize.pipeline.extract_audio")
    @patch("reel_summarize.pipeline.extract_frames")
    @patch("reel_summarize.pipeline.transcribe")
    @patch("reel_summarize.pipeline.analyze_frames")
    @patch("reel_summarize.pipeline.generate_summary")
    def test_pipeline_flow(self, mock_summary, mock_vision, mock_transcribe,
                           mock_frames, mock_audio, mock_download):
        mock_download.return_value = {
            "video_path": "/tmp/v.mp4",
            "metadata": {"caption": "test", "author": "user", "duration": 30},
        }
        mock_audio.return_value = "/tmp/audio.wav"
        mock_frames.return_value = ["f1.jpg", "f2.jpg"]
        mock_transcribe.return_value = [{"start": 0.0, "end": 1.0, "text": "hello"}]
        mock_vision.return_value = [{"text": ["hi"], "scene": "test"}]
        mock_summary.return_value = "summary text"

        cfg = Config()
        with patch("builtins.print") as mock_print:
            run("https://instagram.com/reel/xyz", cfg, keep_artifacts=True)
            mock_summary.assert_called_once()
