from __future__ import annotations

from reel_summarize.config import Config


def transcribe(audio_path: str, cfg: Config) -> list[dict]:
    import whisper

    model = whisper.load_model(cfg.whisper_model)
    result = model.transcribe(audio_path)
    segments = []
    for seg in result.get("segments", []):
        segments.append({
            "start": seg.get("start", 0),
            "end": seg.get("end", 0),
            "text": seg.get("text", "").strip(),
        })
    return segments


def transcribe_text(segments: list[dict]) -> str:
    return " ".join(s["text"] for s in segments if s["text"])
