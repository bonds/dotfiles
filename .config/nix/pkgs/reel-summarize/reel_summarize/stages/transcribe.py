from __future__ import annotations

from reel_summarize.config import Config


def transcribe(audio_path: str, cfg: Config) -> list[dict]:
    from faster_whisper import WhisperModel

    model = WhisperModel(cfg.whisper_model, device="cpu", compute_type="int8")
    segments, _info = model.transcribe(audio_path)
    result = []
    for seg in segments:
        result.append({
            "start": seg.start,
            "end": seg.end,
            "text": seg.text.strip(),
        })
    return result


def transcribe_text(segments: list[dict]) -> str:
    return " ".join(s["text"] for s in segments if s["text"])
