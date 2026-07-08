import json
import os
import tempfile
import unittest
from unittest.mock import patch, MagicMock
from reel_summarize.config import Config
from reel_summarize.stages.download import download
from reel_summarize.stages.audio_extract import extract_audio
from reel_summarize.stages.frame_extract import extract_frames


class TestDownload(unittest.TestCase):
    @patch("reel_summarize.stages.download.subprocess.run")
    def test_download_success(self, mock_run):
        mock_run.return_value.returncode = 0
        mock_run.return_value.stdout = json.dumps({
            "description": "cool reel",
            "uploader": "user",
            "duration": 30,
        })
        with tempfile.TemporaryDirectory() as tmp:
            result = download("https://instagram.com/reel/xyz", tmp)
            self.assertIn("video_path", result)
            self.assertEqual(result["metadata"]["caption"], "cool reel")

    @patch("reel_summarize.stages.download.subprocess.run")
    def test_download_failure(self, mock_run):
        mock_run.return_value.returncode = 1
        mock_run.return_value.stderr = "HTTP Error 404"
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(SystemExit):
                download("https://instagram.com/reel/bad", tmp)


class TestAudioExtract(unittest.TestCase):
    @patch("reel_summarize.stages.audio_extract.subprocess.run")
    def test_extract(self, mock_run):
        mock_run.return_value.returncode = 0
        with tempfile.TemporaryDirectory() as tmp:
            video = os.path.join(tmp, "reel.mp4")
            open(video, "w").close()
            result = extract_audio(video, tmp)
            self.assertEqual(result, os.path.join(tmp, "audio.wav"))


class TestFrameExtract(unittest.TestCase):
    @patch("reel_summarize.stages.frame_extract.subprocess.run")
    @patch("reel_summarize.stages.frame_extract.glob.glob")
    def test_extract_frames(self, mock_glob, mock_run):
        mock_run.return_value.returncode = 0
        mock_glob.return_value = ["frame_0001.jpg", "frame_0002.jpg"]
        cfg = Config()
        with tempfile.TemporaryDirectory() as tmp:
            video = os.path.join(tmp, "reel.mp4")
            open(video, "w").close()
            frames = extract_frames(video, tmp, cfg)
            self.assertEqual(len(frames), 2)
