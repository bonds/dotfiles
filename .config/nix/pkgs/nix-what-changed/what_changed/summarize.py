from __future__ import annotations

import asyncio
import difflib
import json
import re
import sys

import httpx

from what_changed.config import Config
from what_changed.spellfix import fix as _spellfix


class SummaryError(Exception):
    """Raised when the LLM summary cannot be produced (backend unreachable,
    model unavailable, non-200, or timeout). Carries a user-facing message."""

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message

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


# ── Version-range trimming ──────────────────────────────────────────────
#
# Whole-file changelogs (CHANGELOG.md, NEWS, RELEASES.md, HISTORY.rst, …)
# list every release newest-first.  Without trimming, older releases' entries
# leak into the summary — the old prompt only said "pick the most recent
# version", with no hard scope on the old→new window.  _slice_version_range
# cuts the raw text to exactly the version range before the LLM sees it, and
# the range is also spelled out in the prompt.

_UNDERLINE_RE = re.compile(r"^[=\-~^!]{3,}$")
_HEADER_PREFIX_RE = re.compile(r"^(Version |Release |Changes in |v?\d+(?:\.\d+)+)")


def _find_section(text: str, version: str) -> tuple[int | None, int]:
    """Locate the changelog section header for *version*.

    Returns (start_offset, strength): strength 2 for an unambiguous header
    (a markdown heading, or a line underlined with ===/--- like RELEASES.md /
    HISTORY.rst), 1 for a weaker bare-version line, and (None, 0) when nothing
    header-like is found.  The negative lookahead keeps e.g. "1.98.0" from
    matching a longer "1.98.05" or a "1.98.0.1" section.
    """
    if not version:
        return None, 0
    needle = re.compile(re.escape(version) + r"(?![\d.])")
    for m in needle.finditer(text):
        line_start = text.rfind("\n", 0, m.start()) + 1
        line_end = text.find("\n", m.start())
        if line_end == -1:
            line_end = len(text)
        s = text[line_start:line_end].strip()
        if not s:
            continue
        if s.startswith("#"):  # markdown heading
            return line_start, 2
        rest = text[line_end + 1:]
        nxt = rest.split("\n", 1)[0].strip() if rest else ""
        if nxt and _UNDERLINE_RE.match(nxt):  # RST-style underlined heading
            return line_start, 2
        if _HEADER_PREFIX_RE.match(s) and len(s) < 100:  # bare-version line
            return line_start, 1
    return None, 0


def _slice_version_range(
    text: str,
    old_version: str | None,
    new_version: str | None,
) -> str:
    """Return *text* trimmed to the old_version..new_version changelog window.

    When both the new and old version's section headers are found the text is
    cut to the window — headers may be strong (markdown/underlined) or weak
    (bare-version lines like obsidian's '1.14.1').  Single-header finds only
    trigger on unambiguous (strength 2) headers, so a scraped page is never
    truncated mid-content on a false match.  Falls back to the full text when
    the range can't be located; the prompt still names the versions.
    """
    if not old_version or not new_version or old_version == new_version:
        return text
    n_start, n_strength = _find_section(text, new_version)
    o_start, o_strength = _find_section(text, old_version)
    if n_start is not None and o_start is not None:
        # normal newest-first order: keep the new section up to the old header
        return text[n_start:o_start] if n_start < o_start else text[n_start:]
    if n_start is not None and n_strength == 2:
        return text[n_start:]
    if o_start is not None and o_strength == 2:
        return text[:o_start]
    return text


# Commit feeds (the changelog source for what-changed / polyptych) carry no
# version sections — the version lives in the commit subject, e.g.
# "17e5fdd what-changed: trim summaries (v0.21.3)".  Those markers delimit
# releases (newest-first), so slice between the new version's marker and the
# next older marker instead of looking for section headers.

_COMMIT_SHA_RE = re.compile(r"^[0-9a-f]{7,12}\s+\S")


def _looks_like_commit_feed(text: str) -> bool:
    """True when *text* is a prettified GitHub commit list (one '<sha> <subject>'
    per line, as produced by _prettify_gh_commits)."""
    lines = [l for l in text.splitlines() if l.strip()]
    return bool(lines) and all(_COMMIT_SHA_RE.match(l) for l in lines)


def _slice_commit_feed(
    text: str,
    old_version: str | None,
    new_version: str | None,
) -> str:
    """Trim a prettified commit feed to the old_version..new_version window.

    Keeps the commits from the first subject mentioning the new version up to
    the next subject mentioning an older version (unmarked commits between the
    two markers are part of the new release and stay).  Falls back to the full
    text when no marker for either version is found.
    """
    if not old_version or not new_version or old_version == new_version:
        return text
    new_pat = re.compile(r"v?" + re.escape(new_version) + r"(?![\d.])")
    old_pat = re.compile(r"v?" + re.escape(old_version) + r"(?![\d.])")
    ver_pat = re.compile(r"v?\d+(?:\.\d+)+")
    lines = text.splitlines(keepends=True)
    n_i = next((i for i, l in enumerate(lines) if new_pat.search(l)), None)
    o_i = next((i for i, l in enumerate(lines) if old_pat.search(l)), None)
    if n_i is None and o_i is None:
        return text
    if n_i is not None and o_i is not None:
        # normal newest-first order: keep the new release up to the old marker
        return "".join(lines[n_i:o_i]) if n_i < o_i else "".join(lines[n_i:])
    if n_i is not None:
        end = next(
            (i for i in range(n_i + 1, len(lines))
             if ver_pat.search(lines[i]) and not new_pat.search(lines[i])),
            len(lines),
        )
        return "".join(lines[n_i:end])
    # only the old marker found: keep everything above it (all newer commits)
    return "".join(lines[:o_i])


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
        "Never invent changes — only include items explicitly present in the text. "
    ),
    "generic": (
        "Below is the changelog. "
    ),
}

CURATE_PROMPTS = {
    "release": (
        "Below are structured release notes. "
        "Select the most important changes a user would notice — "
        "new features, breaking changes, and important bug fixes. "
        "Never invent changes — only select items explicitly present in the text. "
    ),
    "wiki": (
        "Below is a wiki changelog. "
        "Select the most relevant technical changes and improvements. "
        "Ignore administrative notes, release schedules, and deprecation warnings. "
    ),
    "changelog": (
        "Below is a raw changelog. "
        "Select the most recent version's most important changes. "
        "Never invent changes — only select items explicitly present in the text. "
    ),
    "generic": (
        "Below is the changelog. "
        "Never invent changes — only select items explicitly present in the text. "
    ),
}


async def preflight(cfg: Config, status: callable = lambda **kw: None) -> bool:
    """Ensure the model is available. Shows download progress via *status*(desc=...).

    Returns True if the model is ready, False on error.
    """
    try:
        async with httpx.AsyncClient(timeout=10) as c:
            resp = await c.post(f"{cfg.host}/api/show", json={"name": cfg.model})
            if resp.status_code == 200:
                return True
    except Exception:
        pass
    try:
        status(desc=f"Downloading {cfg.model}...")
        async with httpx.AsyncClient(timeout=300) as c:
            async with c.stream("POST", f"{cfg.host}/api/pull", json={"name": cfg.model}) as resp:
                async for line in resp.aiter_lines():
                    if not line.strip():
                        continue
                    data = json.loads(line)
                    total = data.get("total", 0)
                    completed = data.get("completed", 0)
                    digest = data.get("digest", "")[:12]
                    if total and completed:
                        pct = int(completed * 100 / total)
                        status(desc=f"Downloading {cfg.model}  {digest} {pct}%")
        status(desc="Loading model...")
        async with httpx.AsyncClient(timeout=300) as c:
            await c.post(f"{cfg.host}/api/generate", json={
                "model": cfg.model,
                "prompt": "ok",
                "stream": False,
                "options": {"num_predict": 1},
            })
    except Exception:
        return False
    return True


async def _call_ollama(prompt: str, cfg: Config) -> str | None:
    data = json.dumps({
        "model": cfg.model,
        "prompt": prompt,
        "stream": False,
        "options": {"num_predict": 128},
    })
    url = f"{cfg.host}/api/generate"
    last_err = ""
    for attempt in range(2):
        try:
            async with httpx.AsyncClient(timeout=cfg.timeout) as c:
                resp = await c.post(url, content=data, headers={"Content-Type": "application/json"})
                try:
                    resp.raise_for_status()
                except httpx.HTTPStatusError as e:
                    raise SummaryError(
                        f"ollama backend {cfg.host} -> HTTP {resp.status_code} for model {cfg.model!r} "
                        f"({resp.text[:120]!r}). Check that the right model is pulled/served."
                    ) from e
                return resp.json().get("response", "")
        except SummaryError:
            raise
        except Exception as exc:
            last_err = f"{type(exc).__name__}: {exc}"
            if attempt < 1:
                await asyncio.sleep(2)
    raise SummaryError(
        f"could not reach ollama backend at {cfg.host} (model {cfg.model!r}): {last_err}. "
        f"Run `curl {cfg.host}/api/tags` to check availability."
    )


async def _call_openai(prompt: str, cfg: Config) -> str | None:
    data = json.dumps({
        "model": cfg.model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 128,
    })
    host = cfg.host.rstrip("/")
    url = f"{host}/chat/completions"
    last_err = ""
    for attempt in range(2):
        try:
            async with httpx.AsyncClient(timeout=cfg.timeout) as c:
                resp = await c.post(url, content=data, headers={"Content-Type": "application/json"})
                try:
                    resp.raise_for_status()
                except httpx.HTTPStatusError as e:
                    raise SummaryError(
                        f"OpenAI-compatible backend {host} -> HTTP {resp.status_code} for model {cfg.model!r} "
                        f"({resp.text[:120]!r}). Verify the model name and that the server is the right "
                        f"one (config model={cfg.model!r}, host={cfg.host!r})."
                    ) from e
                return resp.json()["choices"][0]["message"]["content"]
        except SummaryError:
            raise
        except Exception as exc:
            last_err = f"{type(exc).__name__}: {exc}"
            if attempt < 1:
                await asyncio.sleep(2)
    raise SummaryError(
        f"could not reach OpenAI-compatible backend at {host} (model {cfg.model!r}): {last_err}. "
        f"Check that the server is running and reachable (config host={cfg.host!r})."
    )


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
        b = b.replace("`", "")
        if cfg.prompt_style != "curate":
            b = re.sub(r"(\w+)\s+\1", r"\1", b)
            b = re.sub(r"([a-z])([A-Z])", r"\1 \2", b)
            b = re.sub(r"\b(\w{4,})\s+(\1\w{1,3})\b", r"\2", b)
            b = re.sub(r"\b(\w)\1(\w{2,})\b", r"\1\2", b)
            b = _spellfix(b)
            for wrong, right in KNOWN_MERGES.items():
                b = b.replace(wrong, right)
        b = b.strip()
        if b:
            result.append(b)
    return result


_VERSION_TAG_RE = re.compile(r"\((?:v)?(\d+(?:\.\d+)+)\)")


def _sort_bullets_by_version(bullets: list[str]) -> list[str]:
    """Sort summary bullets newest-version-first.

    A -N window can span several sub-releases and the model doesn't always
    keep them ordered, so normalize to descending version-tag order.  Bullets
    carrying a '(vX.Y.Z)' tag sort by that version; untagged bullets keep
    their original relative order at the end (stable sort).
    """
    def key(b: str) -> tuple[int, tuple[int, ...]]:
        m = _VERSION_TAG_RE.search(b)
        if not m:
            return (1, ())
        nums = [int(p) for p in m.group(1).split(".")]
        while len(nums) < 3:
            nums.append(0)
        return (0, tuple(-n for n in nums))
    return sorted(bullets, key=key)


def _smarter_truncate(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    truncated = text[:limit]
    # prefer heading boundary, then double newline, then single newline
    for sep in ("\n## ", "\n# ", "\n\n", "\n    *", "\n"):
        pos = truncated.rfind(sep)
        if pos > limit * 0.4:
            return text[:pos]
    return truncated


PROMPT_STYLES = {
    "default": (
        "{source_prompt}"
        "Do NOT describe what {pkg} is or does. "
        "Write 3-{max} specific bullet points. "
        "Include PR numbers, commit hashes, or version bumps if present. "
        "No generic filler. Respond in English.\n\n"
        "{text}"
    ),
    "strict": (
        "{source_prompt}"
        "Do NOT describe what {pkg} is or does. "
        "Write EXACTLY {max} bullet points. Not more, not fewer. "
        "Include PR numbers or commit hashes if present. "
        "Start each bullet with a dash followed by a space. "
        "No preamble, no summary — just the bullets.\n\n"
        "{text}"
    ),
    "concise": (
        "{source_prompt}"
        "Summarize the key changes in {max} bullet points. "
        "One sentence per bullet. "
        "Never invent changes not in the text. "
        "Be concise.\n\n"
        "{text}"
    ),
    "no-hallucinate": (
        "{source_prompt}"
        "Do NOT describe what {pkg} is or does. "
        "Write 3-{max} bullet points. "
        "CRITICAL: Only include changes that are EXPLICITLY mentioned in the text below. "
        "Do not add any bullet points that are not directly supported. "
        "Include specific details like PR numbers or version numbers when present. "
        "No preamble, no summary — just the bullets.\n\n"
        "{text}"
    ),
    "curate": (
        "{source_prompt}"
        "Select EXACTLY {max} of the most important changes. "
        "For each, quote the original text but trim to the essential detail — "
        "keep the original wording, do not rephrase or rewrite. "
        "Start each bullet with a dash followed by a space. "
        "No preamble, no summary — just the bullets.\n\n"
        "{text}"
    ),
    "numbered": (
        "{source_prompt}"
        "Do NOT describe what {pkg} is or does. "
        "Write exactly 3-{max} numbered bullet points (1., 2., 3., ...). "
        "Include PR numbers or commit hashes if present. "
        "No introductory text — start directly with the first number.\n\n"
        "{text}"
    ),
}


def _version_scope_instruction(old_version: str, new_version: str) -> str:
    """Prompt suffix scoping the summary to the old→new window.

    Asks the model to ignore other versions AND to keep each item's original
    version tag (e.g. '(v0.21.3)' in a commit subject) as-is instead of
    relabelling everything to the new version — a -N window often spans
    several sub-releases, so the tags are the only way to tell them apart.
    """
    return (
        f"This changelog covers {new_version} and possibly older entries. "
        f"Summarize ONLY the changes introduced in {new_version} "
        f"compared to the previous version {old_version}. "
        f"Explicitly ignore anything belonging to another version. "
        f"Keep each item's original version tag (like \"(v{old_version})\") as-is "
        f"when one is present; do not relabel it to {new_version}. "
    )


def _commit_feed_bullets(text: str) -> list[str]:
    """Deterministic canonical lines for a commit feed — the subject only.

    These are the only strings that may appear as summary bullets for a
    commit feed: strip the sha and any leading '<module>: ' prefix, keep the
    subject and its (vX.Y.Z) tag.  Used as the verbatim vocabulary the model
    is allowed to select from.
    """
    out = []
    for line in text.splitlines():
        parts = line.split(None, 1)
        if len(parts) != 2 or not re.fullmatch(r"[0-9a-f]{7,12}", parts[0]):
            continue
        subj = re.sub(r"^[A-Za-z0-9_-]+:\s+", "", parts[1], count=1).strip()
        if subj:
            out.append(subj)
    return out


def _best_match(bullet: str, candidates: list[str]) -> str | None:
    """Return the candidate line *bullet* most closely echoes, or None.

    Verbatim contract: candidates (real changelog lines) are the only allowed
    output, so an invented bullet must not survive.  Exact/substring
    containment wins (handles the model trimming a line); otherwise fall back
    to a difflib similarity threshold.
    """
    nb = bullet.strip().lower()
    if nb:
        for cand in candidates:
            nc = cand.lower()
            if nb == nc or nb in nc or nc in nb:
                return cand
    best, best_ratio = None, 0.0
    for cand in candidates:
        r = difflib.SequenceMatcher(None, nb, cand.lower()).ratio()
        if r > best_ratio:
            best, best_ratio = cand, r
    return best if best_ratio >= 0.6 else None


def _select_verbatim(
    model_bullets: list[str], candidates: list[str], cfg: Config
) -> list[str]:
    """Emit the candidates the model selected, verbatim and newest-first.

    The model's only job is choosing which lines are interesting — it must not
    be the source of wording.  Drop bullets that don't echo any real line
    (invented ones); then top up with any un-selected candidates the budget
    still allows, so a short window never loses real changes because the model
    under-selected.  If the model produced nothing usable, fall back to all
    candidates rather than an empty or fabricated summary.
    """
    kept: list[str] = []
    for b in model_bullets:
        m = _best_match(b, candidates)
        if m is not None and m not in kept:
            kept.append(m)
    if not kept:
        kept = list(candidates)
    for c in candidates:
        if len(kept) >= cfg.max_bullets:
            break
        if c not in kept:
            kept.append(c)
    return _sort_bullets_by_version(kept)[:cfg.max_bullets]


async def summarize(
    pkg_name: str,
    changelog_text: str,
    cfg: Config,
    old_version: str | None = None,
    new_version: str | None = None,
) -> list[str] | None:
    if len(changelog_text) < 100:
        return None
    text = changelog_text
    if _looks_like_commit_feed(text):
        text = _slice_commit_feed(text, old_version, new_version)
    text = _slice_version_range(text, old_version, new_version)
    text = _smarter_truncate(text, cfg.max_input_bytes)
    is_commit_feed = _looks_like_commit_feed(text)
    # For a commit feed the model only SELECTS the interesting lines — it must
    # not be the source of wording — so cap the requested count at the number
    # of commits (asking for EXACTLY 5 with 2 commits invites invented filler).
    max_bullets = cfg.max_bullets
    if is_commit_feed and cfg.prompt_style == "curate":
        max_bullets = max(
            1, min(max_bullets, sum(1 for l in text.splitlines() if l.strip()))
        )
    stype = _detect_source_type(text)
    prompts = CURATE_PROMPTS if cfg.prompt_style == "curate" else PROMPTS
    style = PROMPT_STYLES.get(cfg.prompt_style, PROMPT_STYLES["default"])
    source_prompt = prompts[stype]
    if old_version and new_version:
        source_prompt += _version_scope_instruction(old_version, new_version)
    prompt = style.format(
        source_prompt=source_prompt,
        pkg=pkg_name,
        max=max_bullets,
        text=text,
    )
    response = await _call_llm(prompt, cfg)
    if not response:
        return None
    bullets, _non_bullets = _parse_bullets(response)
    if not bullets:
        return None
    if is_commit_feed:
        return _select_verbatim(bullets, _commit_feed_bullets(text), cfg)
    return _sort_bullets_by_version(_postprocess(bullets, cfg))
