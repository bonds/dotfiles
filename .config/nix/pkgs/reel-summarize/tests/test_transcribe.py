import sys
import unittest
from unittest.mock import MagicMock, patch
from reel_summarize.config import Config
from reel_summarize.stages.transcribe import transcribe, transcribe_text


class TestTranscribe(unittest.TestCase):
    def _make_mock_whisper(self):
        mock_whisper = MagicMock()
        mock_model = MagicMock()
        mock_whisper.WhisperModel.return_value = mock_model
        seg = MagicMock()
        seg.start = 0.0
        seg.end = 1.5
        seg.text = "hello world"
        mock_model.transcribe.return_value = ([seg], None)
        return mock_whisper

    def test_transcribe(self):
        mock_whisper = self._make_mock_whisper()
        cfg = Config()
        with patch.dict('sys.modules', {'faster_whisper': mock_whisper}):
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
