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
    if cfg.backend == "openai":
        return _call_openai(prompt, cfg)
    return _call_ollama(prompt, cfg)


def _call_ollama(prompt: str, cfg: Config) -> str:
    import httpx

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
        print(f"  error: cannot reach LLM at {cfg.host}: {e}", file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f"  error during summarization: {e}", file=sys.stderr)
        sys.exit(1)


def _call_openai(prompt: str, cfg: Config) -> str:
    import httpx

    host = cfg.host.rstrip("/")
    payload = {
        "model": cfg.summarize_model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 512,
        "stream": False,
    }
    try:
        resp = httpx.post(
            f"{host}/chat/completions",
            json=payload,
            timeout=cfg.timeout,
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"].strip()
    except httpx.RequestError as e:
        print(f"  error: cannot reach LLM at {cfg.host}: {e}", file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f"  error during summarization: {e}", file=sys.stderr)
        sys.exit(1)
