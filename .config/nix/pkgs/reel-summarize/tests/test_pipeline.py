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
            kwargs = mock_summary.call_args.kwargs
            self.assertEqual(kwargs.get("platform"), "instagram")


class TestYouTubePipeline(unittest.TestCase):
    """YouTube flow: no extract_frames, no analyze_frames, platform=youtube."""

    @patch("reel_summarize.pipeline._ensure_whisper_model")
    @patch("reel_summarize.pipeline.fetch_captions")
    @patch("reel_summarize.pipeline.fetch_youtube_metadata")
    @patch("reel_summarize.pipeline.download_audio")
    @patch("reel_summarize.pipeline.extract_audio")
    @patch("reel_summarize.pipeline.extract_frames")
    @patch("reel_summarize.pipeline.transcribe")
    @patch("reel_summarize.pipeline.analyze_frames")
    @patch("reel_summarize.pipeline.generate_summary")
    def test_youtube_flow_skips_vision(self, mock_summary, mock_vision,
                                       mock_transcribe, mock_frames, mock_audio,
                                       mock_dl_audio, mock_meta, mock_caps,
                                       mock_whisper_model):
        mock_meta.return_value = {
            "caption": "A video", "author": "chan", "duration": 30,
            "is_live": False,
        }
        mock_dl_audio.return_value = "/tmp/audio_src.webm"
        mock_audio.return_value = "/tmp/audio.wav"
        mock_caps.return_value = None  # captions unavailable → whisper
        mock_transcribe.return_value = [{"start": 0.0, "end": 1.0, "text": "hello"}]
        mock_summary.return_value = "summary text"

        cfg = Config()
        with patch("builtins.print"):
            run("https://www.youtube.com/watch?v=abc", cfg, keep_artifacts=True)

        mock_summary.assert_called_once()
        kwargs = mock_summary.call_args.kwargs
        self.assertEqual(kwargs.get("platform"), "youtube")
        # frames/vision stages must never run for YouTube
        mock_frames.assert_not_called()
        mock_vision.assert_not_called()

    @patch("reel_summarize.pipeline._ensure_whisper_model")
    @patch("reel_summarize.pipeline.fetch_captions")
    @patch("reel_summarize.pipeline.fetch_youtube_metadata")
    @patch("reel_summarize.pipeline.download_audio")
    @patch("reel_summarize.pipeline.extract_audio")
    @patch("reel_summarize.pipeline.transcribe")
    @patch("reel_summarize.pipeline.generate_summary")
    def test_youtube_captions_used_when_available(self, mock_summary, mock_transcribe,
                                                   mock_audio, mock_dl_audio,
                                                   mock_meta, mock_caps,
                                                   mock_whisper_model):
        mock_meta.return_value = {
            "caption": "A video", "author": "chan", "duration": 30,
            "is_live": False,
        }
        mock_dl_audio.return_value = "/tmp/audio_src.webm"
        mock_audio.return_value = "/tmp/audio.wav"
        mock_caps.return_value = [{"start": 0.0, "end": 1.0, "text": "from captions"}]
        mock_summary.return_value = "summary text"

        cfg = Config(youtube_prefer_captions=True)
        with patch("builtins.print"):
            run("https://youtu.be/abc", cfg, keep_artifacts=True)

        mock_transcribe.assert_not_called()  # captions short-circuit whisper
        mock_summary.assert_called_once()
