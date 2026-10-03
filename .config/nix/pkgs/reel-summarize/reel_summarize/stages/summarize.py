from __future__ import annotations

import sys

from reel_summarize.config import Config
from reel_summarize.errors import SummaryError


_PROMPT_TEMPLATES = {
    "instagram": (
        "You are summarizing an Instagram Reel.\n"
        "Inputs below:\n"
        "- Author: {author}\n"
        "- Original caption: {caption}\n"
        "- Spoken audio transcript: {transcript}\n"
        "- Per-frame on-screen text, scene descriptions, and recognized objects:\n"
        "{vision_timeline}\n"
        "\n"
        "Write a concise prose summary (5-10 sentences) of what the reel is about. "
        "Include both what's said, what's shown on screen, and any key objects/people visible. "
        'Do not use headers or bullet points \u2014 just prose.'
    ),
    "youtube": (
        "You are summarizing a YouTube video.\n"
        "Inputs below:\n"
        "- Channel/author: {author}\n"
        "- Title/description: {caption}\n"
        "- Transcript: {transcript}\n"
        "- Per-frame on-screen text, scene descriptions, and recognized objects:\n"
        "{vision_timeline}\n"
        "\n"
        "Write a concise prose summary (5-10 sentences) of what the video is about, "
        "covering the main points and any concrete conclusions or recommendations. "
        'Do not use headers or bullet points \u2014 just prose.'
    ),
}

_MAP_PROMPT = (
    "You are summarizing part {part} of {total} sequential segments of a YouTube "
    "video transcript ({platform} input).\n"
    "- Channel/author: {author}\n"
    "- Title/description: {caption}\n"
    "- Transcript segment:\n"
    "{transcript}\n"
    "\n"
    "Summarize this segment in 2-4 sentences: main points, names, and any concrete "
    "claims, numbers, or conclusions. Plain prose, no headers or bullets."
)

_REDUCE_PROMPT = (
    "You are summarizing a YouTube video from partial summaries of its transcript "
    "({platform} input).\n"
    "- Channel/author: {author}\n"
    "- Title/description: {caption}\n"
    "- Partial summaries, in transcript order:\n"
    "{transcript}\n"
    "\n"
    "Write a concise prose summary (5-10 sentences) of the whole video: the main "
    "thread, key points, and any concrete conclusions. Do not use headers or "
    "bullet points \u2014 just prose."
)


def _dispatch(prompt: str, cfg: Config) -> str:
    if cfg.backend == "openai":
        return _call_openai(prompt, cfg)
    if cfg.backend == "osaurus":
        return _call_osaurus(prompt, cfg)
    return _call_ollama(prompt, cfg)


def split_text(
    text: str, chunk_chars: int, overlap_chars: int
) -> list[str]:
    """Split *text* into chunks of ≤ ``chunk_chars`` with ``overlap_chars``
    overlap at sentence boundaries (so no sentence is cut in half at a seam).

    ``overlap_chars`` is clamped to stay below half a chunk to guarantee
    forward progress on pathological inputs.
    """
    if len(text) <= chunk_chars:
        return [text]
    overlap = min(overlap_chars, chunk_chars // 2)
    chunks = []
    start = 0
    n = len(text)
    while start < n:
        end = min(start + chunk_chars, n)
        if end < n:
            # snap to the last sentence end within the window
            window = text[start:end]
            cut = max(window.rfind(". "), window.rfind("! "), window.rfind("? "),
                      window.rfind("\n"))
            if cut > 0:
                end = start + cut + 1
        chunks.append(text[start:end])
        if end >= n:
            break
        start = max(end - overlap, start + 1)
    return [c for c in chunks if c.strip()]


def generate_summary(
    transcript: str,
    vision_timeline: str,
    caption: str | None,
    author: str | None,
    cfg: Config,
    platform: str = "instagram",
) -> str:
    """Single-shot summary. Instagram (short reels) always lands here; YouTube
    transcripts under ``cfg.summary_max_chars`` land here too."""
    template = _PROMPT_TEMPLATES.get(platform, _PROMPT_TEMPLATES["instagram"])
    prompt = template.format(
        author=author or "unknown",
        caption=caption or "(no caption)",
        transcript=transcript or "(no spoken audio)",
        vision_timeline=vision_timeline or "(no frames analyzed)",
    )
    return _dispatch(prompt, cfg)


def generate_summary_chunked(
    transcript: str,
    vision_timeline: str,
    caption: str | None,
    author: str | None,
    cfg: Config,
    platform: str = "instagram",
) -> str:
    """Map-reduce summary for long transcripts (e.g. a 46-min YouTube video
    whose text overflows a 32k-context model).

    Chunks the transcript (~24k chars, ~1k overlap), summarizes each chunk
    (map), then reduces the partial summaries into the final prose answer.
    Falls back to the single-shot path when the transcript fits in one chunk.
    """
    if len(transcript) <= cfg.summary_max_chars:
        return generate_summary(transcript, vision_timeline, caption, author, cfg, platform)

    chunks = split_text(transcript, cfg.mapreduce_chunk_chars, cfg.mapreduce_overlap_chars)
    partials = []
    total = len(chunks)
    for i, chunk in enumerate(chunks, 1):
        print(f"  → summarizing chunk {i}/{total} ({len(chunk)} chars)...",
              file=sys.stderr, flush=True)
        prompt = _MAP_PROMPT.format(
            part=i, total=total, platform=platform,
            author=author or "unknown",
            caption=caption or "(no caption)",
            transcript=chunk,
        )
        partials.append(_dispatch(prompt, cfg))

    joined = "\n\n".join(
        f"[segment {i}] {p}" for i, p in enumerate(partials, 1) if p
    )
    print(f"  → reducing {total} partial summaries...", file=sys.stderr, flush=True)
    prompt = _REDUCE_PROMPT.format(
        platform=platform,
        author=author or "unknown",
        caption=caption or "(no caption)",
        transcript=joined,
    )
    return _dispatch(prompt, cfg)


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
        raise SummaryError(f"cannot reach LLM at {cfg.host}: {e}") from e
    except Exception as e:
        raise SummaryError(f"error during summarization: {e}") from e


def _call_openai(prompt: str, cfg: Config) -> str:
    import httpx

    host = cfg.host.rstrip("/")
    payload = {
        "model": cfg.summarize_model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 2048,
        "stream": False,
    }
    try:
        resp = httpx.post(
            f"{host}/v1/chat/completions",
            json=payload,
            timeout=cfg.timeout,
        )
        resp.raise_for_status()
        msg = resp.json()["choices"][0]["message"]
        content = (msg.get("content") or "").strip()
        # Some reasoning models (e.g. qwen3) emit the answer as
        # reasoning_content and leave content empty when the token
        # budget is spent thinking — fall back so we never return "".
        if not content:
            content = (msg.get("reasoning_content") or "").strip()
        return content
    except httpx.RequestError as e:
        raise SummaryError(f"cannot reach LLM at {cfg.host}: {e}") from e
    except Exception as e:
        raise SummaryError(f"error during summarization: {e}") from e


def _call_osaurus(prompt: str, cfg: Config) -> str:
    import httpx

    host = cfg.host.rstrip("/")
    headers = {}
    if cfg.osaurus_api_key:
        headers["Authorization"] = f"Bearer {cfg.osaurus_api_key}"

    # Auto-detect the actual model from the server
    model = cfg.summarize_model
    try:
        resp = httpx.get(f"{host}/v1/models", headers=headers, timeout=5)
        resp.raise_for_status()
        models = resp.json().get("data", [])
        if models:
            model = models[0].get("id", model)
    except Exception:
        pass

    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 2048,
        "stream": False,
    }
    try:
        resp = httpx.post(
            f"{host}/v1/chat/completions",
            json=payload,
            headers=headers,
            timeout=cfg.timeout,
        )
        resp.raise_for_status()
        msg = resp.json()["choices"][0]["message"]
        content = (msg.get("content") or "").strip()
        if not content:
            content = (msg.get("reasoning_content") or "").strip()
        return content
    except httpx.RequestError as e:
        raise SummaryError(f"cannot reach Osaurus at {cfg.host}: {e}") from e
    except Exception as e:
        raise SummaryError(f"error during summarization: {e}") from e
