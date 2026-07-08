import importlib.util
import unittest
from unittest.mock import MagicMock, patch
from reel_summarize.config import Config
from reel_summarize.stages.transcribe import transcribe, transcribe_text


@unittest.skipIf(
    importlib.util.find_spec("faster_whisper") is None,
    "faster-whisper not installed (nix-managed dep)"
)
class TestTranscribe(unittest.TestCase):
    @patch("faster_whisper.WhisperModel")
    def test_transcribe(self, mock_model_cls):
        mock_model = MagicMock()
        mock_model_cls.return_value = mock_model

        seg = MagicMock()
        seg.start = 0.0
        seg.end = 1.5
        seg.text = "hello world"
        mock_model.transcribe.return_value = ([seg], None)

        cfg = Config()
        segments = transcribe("/tmp/audio.wav", cfg)
        self.assertEqual(len(segments), 1)
        self.assertEqual(segments[0]["text"], "hello world")


class TestTranscribeText(unittest.TestCase):
    def test_transcribe_text(self):
        segments = [
            {"start": 0.0, "end": 1.0, "text": "hello"},
            {"start": 1.0, "end": 2.0, "text": "world"},
        ]
        self.assertEqual(transcribe_text(segments), "hello world")
