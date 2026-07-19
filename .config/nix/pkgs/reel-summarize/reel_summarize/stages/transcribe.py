from __future__ import annotations

import sys

import numpy as np

from reel_summarize.config import Config, whisper_model_path


def transcribe(audio_path: str, cfg: Config) -> list[dict]:
    import time
    import transcribe_cpp

    # Read the 16kHz mono WAV file into float32 PCM
    # ffmpeg already converted to 16kHz mono WAV in audio_extract.py
    import wave

    with wave.open(audio_path, "rb") as wf:
        assert wf.getframerate() == 16000, f"Expected 16kHz, got {wf.getframerate()}Hz"
        assert wf.getnchannels() == 1, f"Expected mono, got {wf.getnchannels()} channels"
        raw = wf.readframes(wf.getnframes())

    pcm = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    duration_s = len(pcm) / 16000

    t0 = time.monotonic()
    result = transcribe_cpp.transcribe(whisper_model_path(cfg), pcm)
    elapsed = time.monotonic() - t0
    print(f"  ⏱ transcription: {elapsed:.2f}s for {duration_s:.1f}s audio ({duration_s/elapsed:.1f}x realtime)", file=sys.stderr, flush=True)

    segments = []
    for seg in result.segments:
        segments.append({
            "start": seg.t0_ms / 1000,
            "end": seg.t1_ms / 1000,
            "text": seg.text.strip(),
        })
    return segments


def transcribe_text(segments: list[dict]) -> str:
    return " ".join(s["text"] for s in segments if s["text"])
