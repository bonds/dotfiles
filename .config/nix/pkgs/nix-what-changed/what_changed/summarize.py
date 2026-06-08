from __future__ import annotations

import asyncio
import json
import re

import httpx

from what_changed.config import Config

KNOWN_MERGES = {
    "mimallocator": "mimalloc allocator",
    "backendriver": "backend driver",
    "versionumber": "version number",
    "removedue": "removed due",
    "addresspace": "address space",
    "featuresuch": "feature such",
    "argumento": "argument to",
    "weremoved": "were removed",
    "removedeprecated": "removed deprecated",
    "thexcerpt": "the excerpt",
    "formathe": "for the",
    "revisionumbers": "revision numbers",
    "isupported": "is supported",
    "wereduced": "were reduced",
    "aremployed": "are employed",
    "withe": "with the",
    "andling": "and handling",
    "ecoding": "encoding",
    "irectoken": "direct token",
    "upporthrough": "support through",
    "ockets": "sockets",
    "ystem": "system",
    "pecific": "specific",
    "inpm": "in npm",
    "returnil": "return nil",
    "wheno": "when no",
    "fixeshell": "fix shell",
    "forility": "for utility",
    "orkernel": "or kernel",
    "lleaks": "leaks",
    "andecoding": "and decoding",
    "morefficiently": "more efficiently",
    "specifich": "specific",
    "ommandsuch": "command such",
    "portra": "portrait",
    "errored": "error",
    "luded": "included",
    "nto": "into",
    "ancelled": "cancelled",
    "ilable": "available",
    "emulation": "emulation",
    "ystem": "system",
    "githubuntu": "github ubuntu",
    "incorrectimestamps": "incorrect timestamps",
    "variouscenarios": "various scenarios",
}


def _detect_source_type(text: str) -> str:
    lines = text.splitlines()
    non_empty = [l for l in lines if l.strip()]
    if not non_empty:
        return "generic"
    bullet_likes = sum(
        1 for l in non_empty if re.match(r"^\s*[\*\-]|^\d+[\.\)]\s", l)
    )
    ratio = bullet_likes / len(non_empty)
    if ratio > 0.3:
        return "release"
    avg_len = sum(len(l) for l in non_empty) / len(non_empty)
    if avg_len > 200:
        return "wiki"
    return "changelog"


PROMPTS = {
    "release": (
        "Below are structured release notes. "
        "Summarize ONLY the specific changes the user would notice. "
        "Focus on new features, breaking changes, and important bug fixes. "
    ),
    "wiki": (
        "Below is a wiki changelog. "
        "Extract the specific technical changes and improvements. "
        "Ignore administrative notes, release schedules, and deprecation warnings. "
    ),
    "changelog": (
        "Below is a raw changelog. "
        "Pick the most recent version's changes and summarize them. "
    ),
    "generic": (
        "Below is the changelog. "
    ),
}


_model_checked = False


def _ensure_model(cfg: Config):
    global _model_checked
    if _model_checked:
        return
    _model_checked = True
    import subprocess
    try:
        result = subprocess.run(["ollama", "list"], capture_output=True, text=True, timeout=10)
        if cfg.model not in result.stdout:
            print(f"  (pulling {cfg.model}…)", file=__import__("sys").stderr)
            subprocess.run(["ollama", "pull", cfg.model], timeout=300)
    except Exception:
        pass


async def _call_ollama(prompt: str, cfg: Config) -> str | None:
    _ensure_model(cfg)
    data = json.dumps({
        "model": cfg.model,
        "prompt": prompt,
        "stream": False,
        "options": {"num_predict": 512},
    })
    for attempt in range(2):
        try:
            async with httpx.AsyncClient(timeout=cfg.timeout) as c:
                resp = await c.post(f"{cfg.host}/api/generate", content=data, headers={"Content-Type": "application/json"})
                resp.raise_for_status()
                return resp.json().get("response", "")
        except Exception:
            if attempt < 1:
                await asyncio.sleep(2)
    return None


async def _call_openai(prompt: str, cfg: Config) -> str | None:
    data = json.dumps({
        "model": cfg.model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 512,
    })
    host = cfg.host.rstrip("/")
    for attempt in range(2):
        try:
            async with httpx.AsyncClient(timeout=cfg.timeout) as c:
                resp = await c.post(f"{host}/chat/completions", content=data, headers={"Content-Type": "application/json"})
                resp.raise_for_status()
                return resp.json()["choices"][0]["message"]["content"]
        except Exception:
            if attempt < 1:
                await asyncio.sleep(2)
    return None


async def _call_llm(prompt: str, cfg: Config) -> str | None:
    if cfg.backend == "openai":
        return await _call_openai(prompt, cfg)
    return await _call_ollama(prompt, cfg)


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
        b = re.sub(r"\b(\w{4,})\s+(\1\w{1,3})\b", r"\2", b)
        for wrong, right in KNOWN_MERGES.items():
            b = b.replace(wrong, right)
        b = b.strip()
        if b:
            result.append(b)
    return result


def _smarter_truncate(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    truncated = text[:limit]
    # prefer heading boundary, then double newline, then single newline
    for sep in ("\n## ", "\n# ", "\n\n", "\n"):
        pos = truncated.rfind(sep)
        if pos > limit * 0.5:
            return text[:pos]
    return truncated


async def summarize(pkg_name: str, changelog_text: str, cfg: Config) -> list[str] | None:
    if len(changelog_text) < 100:
        return None
    text = _smarter_truncate(changelog_text, cfg.max_input_bytes)
    stype = _detect_source_type(text)
    prompt = (
        f"{PROMPTS[stype]}"
        f"Do NOT describe what {pkg_name} is or does. "
        f"Write 3-{cfg.max_bullets} specific bullet points. "
        "Include PR numbers, commit hashes, or version bumps if present. "
        "No generic filler. Respond in English.\n\n"
        f"{text}"
    )
    response = await _call_llm(prompt, cfg)
    if not response:
        return None
    bullets, _non_bullets = _parse_bullets(response)
    if bullets:
        return _postprocess(bullets, cfg)
    return None
