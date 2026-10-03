import os
import sys
import tempfile
import unittest
import wave
from unittest.mock import MagicMock, patch

from reel_summarize.config import Config
from reel_summarize.stages.transcribe import transcribe, transcribe_text


class TestTranscribe(unittest.TestCase):
    def test_transcribe(self):
        """transcribe() reads a 16 kHz mono WAV and maps transcribe_cpp segments."""
        # transcribe_cpp is imported inside the function, so patch sys.modules
        # (a module-level @patch would fail: the module never has the attribute).
        mock_cpp = MagicMock()
        mock_result = MagicMock()
        mock_seg = MagicMock()
        mock_seg.t0_ms = 0
        mock_seg.t1_ms = 1500
        mock_seg.text = "hello world"
        mock_result.segments = [mock_seg]
        mock_cpp.transcribe.return_value = mock_result

        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            path = f.name
        try:
            with wave.open(path, "wb") as wf:
                wf.setnchannels(1)
                wf.setsampwidth(2)
                wf.setframerate(16000)
                wf.writeframes(b"\x00\x00" * 16000)  # 1 s of silence
            cfg = Config()
            with patch.dict(sys.modules, {"transcribe_cpp": mock_cpp}):
                segments = transcribe(path, cfg)
        finally:
            os.unlink(path)

        self.assertEqual(len(segments), 1)
        self.assertEqual(segments[0]["text"], "hello world")
        self.assertEqual(segments[0]["start"], 0.0)
        self.assertEqual(segments[0]["end"], 1.5)
        mock_cpp.transcribe.assert_called_once()
        # model path is the first argument
        self.assertTrue(mock_cpp.transcribe.call_args[0][0].endswith(".gguf"))


class TestTranscribeText(unittest.TestCase):
    def test_transcribe_text(self):
        segments = [
            {"start": 0.0, "end": 1.0, "text": "hello"},
            {"start": 1.0, "end": 2.0, "text": "world"},
        ]
        self.assertEqual(transcribe_text(segments), "hello world")
