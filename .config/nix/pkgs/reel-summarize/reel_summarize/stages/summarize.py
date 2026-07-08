from __future__ import annotations

import sys

from reel_summarize.config import Config


_FINAL_PROMPT = (
    "You are summarizing an Instagram Reel.\n"
    "Inputs below:\n"
    "- Author: {author}\n"
    "- Original caption: {caption}\n"
    "- Spoken audio transcript: {transcript}\n"
    "- Per-frame on-screen text + scene descriptions:\n"
    "{vision_timeline}\n"
    "\n"
    "Write a concise prose summary (5-10 sentences) of what the reel is about. "
    "Include both what's said and what's shown on screen. "
    'Do not use headers or bullet points \u2014 just prose.'
)


def generate_summary(
    transcript: str,
    vision_timeline: str,
    caption: str | None,
    author: str | None,
    cfg: Config,
) -> str:
    import httpx

    prompt = _FINAL_PROMPT.format(
        author=author or "unknown",
        caption=caption or "(no caption)",
        transcript=transcript or "(no spoken audio)",
        vision_timeline=vision_timeline or "(no frames analyzed)",
    )
    payload = {
        "model": cfg.summarize_model,
        "prompt": prompt,
        "stream": False,
        "options": {"num_predict": 512},
    }
    try:
        resp = httpx.post(
            f"{cfg.host}/api/generate",
            json=payload,
            timeout=cfg.timeout,
        )
        resp.raise_for_status()
        return resp.json().get("response", "").strip()
    except httpx.RequestError as e:
        print(f"  error: cannot reach Ollama at {cfg.host}: {e}", file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f"  error during summarization: {e}", file=sys.stderr)
        sys.exit(1)
