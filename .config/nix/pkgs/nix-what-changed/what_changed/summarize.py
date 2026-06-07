from __future__ import annotations

import json
import re
import urllib.request

from what_changed.config import Config


def _call_ollama(prompt: str, cfg: Config) -> str | None:
    data = json.dumps({
        "model": cfg.model,
        "prompt": prompt,
        "stream": False,
        "options": {"num_predict": 512},
    }).encode()
    req = urllib.request.Request(
        f"{cfg.host}/api/generate",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=cfg.timeout) as resp:
            result = json.loads(resp.read())
            return result.get("response", "")
    except Exception:
        return None


def _call_openai(prompt: str, cfg: Config) -> str | None:
    data = json.dumps({
        "model": cfg.model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 512,
    }).encode()
    host = cfg.host.rstrip("/")
    req = urllib.request.Request(
        f"{host}/chat/completions",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=cfg.timeout) as resp:
            result = json.loads(resp.read())
            return result["choices"][0]["message"]["content"]
    except Exception:
        return None


def _call_llm(prompt: str, cfg: Config) -> str | None:
    if cfg.backend == "openai":
        return _call_openai(prompt, cfg)
    return _call_ollama(prompt, cfg)


def _parse_bullets(text: str) -> tuple[list[str], list[str]]:
    bullets: list[str] = []
    non_bullets: list[str] = []
    in_bullets = False
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        if re.match(r"^[\*\-](?!-)|^\d+[\.\)]\s", line):
            in_bullets = True
            line = re.sub(r"^\s*[\*\-\d]+\.?\s*", "", line)
            line = re.sub(r"\*\*", "", line).strip()
            if line:
                bullets.append(line)
        elif re.match(r"^#+[ \t]|^https?://", line):
            continue
        elif in_bullets and bullets:
            line = re.sub(r"\*\*", "", line).strip()
            if line:
                bullets[-1] = f"{bullets[-1]} {line}"
        else:
            non_bullets.append(line)
    filtered = [b for b in bullets if not re.match(r"^v?\d+(\.\d+)+\s*\.?\s*$", b)]
    return filtered, non_bullets


def _postprocess(bullets: list[str], cfg: Config) -> list[str]:
    result = []
    for b in bullets:
        b = re.sub(r"(\w+)\s+\1", r"\1", b)
        b = re.sub(r"([a-z])([A-Z])", r"\1 \2", b)
        b = b.strip()
        if b:
            result.append(b)
    return result


def summarize(pkg_name: str, changelog_text: str, cfg: Config) -> list[str] | None:
    if len(changelog_text) < 100:
        return None
    text = changelog_text[: cfg.max_input_bytes]
    prompt = (
        "Below is the changelog. Summarize ONLY the specific changes. "
        f"Do NOT describe what {pkg_name} is or does. "
        f"Write 3-{cfg.max_bullets} specific bullet points. "
        "Include PR numbers, commit hashes, or version bumps if present. "
        "No generic filler. Respond in English.\n\n"
        f"{text}"
    )
    response = _call_llm(prompt, cfg)
    if not response:
        return None
    bullets, _non_bullets = _parse_bullets(response)
    if bullets:
        return _postprocess(bullets, cfg)
    return None
