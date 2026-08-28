from __future__ import annotations

import asyncio
import json
import re
import subprocess
from html.parser import HTMLParser

import httpx

from what_changed.config import Config


async def _fetch(url: str, cfg: Config) -> str | None:
    headers = {"User-Agent": "what-changed/0.7.0"}
    async with httpx.AsyncClient(
        timeout=httpx.Timeout(cfg.http_timeout),
        follow_redirects=True,
        headers=headers,
    ) as c:
        for attempt in range(3):
            try:
                resp = await c.get(url)
                resp.raise_for_status()
                return resp.text
            except Exception:
                if attempt < 2:
                    await asyncio.sleep(2 ** attempt)
                else:
                    return None
    return None


async def _raw_github(owner: str, repo: str, ref: str, path: str, cfg: Config) -> str | None:
    url = f"https://raw.githubusercontent.com/{owner}/{repo}/{ref}/{path}"
    return await _fetch(url, cfg)


class _HTMLTextExtractor(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.text: list[str] = []
        self.skip = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]):
        if tag in ("script", "style", "nav", "header", "footer"):
            self.skip += 1
        if tag in ("br", "p", "li", "tr", "h1", "h2", "h3", "h4", "dd", "dt", "div"):
            self.text.append("\n")

    def handle_endtag(self, tag: str):
        if tag in ("script", "style", "nav", "header", "footer"):
            self.skip = max(0, self.skip - 1)
        if tag in ("p", "li", "tr", "h1", "h2", "h3", "h4", "dd", "dt", "div"):
            self.text.append("\n")

    def handle_data(self, data: str):
        if self.skip == 0:
            self.text.append(data)


def _extract_text(html: str) -> str | None:
    data = html[:200000]
    if not data.strip():
        return None
    if not re.search(r"(?i)<(?:html|!doctype)\b", data[:500]):
        lines = [l.strip() for l in data.split("\n") if l.strip()]
        return "\n".join(lines) if lines else None
    m = re.search(
        r'<div[^>]*class\s*=\s*"[^"]*\bmw-parser-output\b[^"]*"[^>]*>', data
    )
    if m:
        data = data[m.end():]
    parser = _HTMLTextExtractor()
    parser.feed(data)
    result = "".join(parser.text)
    lines = [l.strip() for l in result.split("\n") if l.strip()]
    return "\n".join(lines) if lines else None


async def _fetch_github_release(owner: str, repo: str, tag: str, cfg: Config) -> str | None:
    try:
        result = subprocess.run(
            ["gh", "release", "view", tag, "--repo", f"{owner}/{repo}", "--json", "body", "--jq", ".body"],
            capture_output=True,
            text=True,
            timeout=cfg.gh_timeout,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    for path in ("ChangeLog", "NEWS", "CHANGES.md", "CHANGELOG.md", "RELEASE_NOTES.md", "NEWS.md"):
        content = await _raw_github(owner, repo, tag, path, cfg)
        if content and re.search(r"(?i)change|fix|version|release|bug", content[:1000]):
            return content
    # Last resort: scrape the GitHub releases page HTML
    html = await _fetch(f"https://github.com/{owner}/{repo}/releases/tag/{tag}", cfg)
    if html:
        text = _extract_text(html)
        if text and len(text) > 200:
            return text
    return None


def _resolve_release_body(json_text: str | None, want: str) -> str | None:
    """From a GitHub releases API JSON response, return the body of the release
    whose title names `want` (e.g. version '0.20.6' matches 'v0.20.6' in
    'Hermes Agent v0.20.6 (v2026.8.27)'). Returns None when nothing matches.

    Used for packages whose release tags do NOT equal their package version
    (e.g. hermes-agent tags releases by date: v2026.8.27). The regex's negative
    lookahead keeps a want of '0.20.6' from matching a longer 'v0.20.60'."""
    if not json_text or not want:
        return None
    try:
        releases = json.loads(json_text)
    except json.JSONDecodeError:
        return None
    if not isinstance(releases, list):
        return None
    pat = re.compile(re.escape(f"v{want}") + r"(?![0-9.])")
    for rel in releases:
        name = rel.get("name") or ""
        if pat.search(name):
            body = (rel.get("body") or "").strip()
            if body:
                return body
    return None


async def fetch_changelog(url: str, cfg: Config) -> str | None:
    m = re.match(r"^https://github\.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)", url)
    if m:
        raw = await _raw_github(m.group(1), m.group(2), m.group(3), m.group(4), cfg)
        return raw[:cfg.max_changelog_bytes] if raw else None

    m = re.match(r"^https://github\.com/([^/]+)/([^/]+)/releases/tag/(.+)", url)
    if m:
        return await _fetch_github_release(m.group(1), m.group(2), m.group(3), cfg)

    # GitHub releases API (resolve_version query): a package whose release tags
    # don't match its version (e.g. hermes-agent) pins the API list URL + the
    # desired version; pick the release body whose title names that version.
    m = re.search(r"^https://api\.github\.com/repos/[^/]+/[^/]+/releases\?", url)
    if m:
        raw = await _fetch(url, cfg)
        if not raw:
            return None
        from urllib.parse import parse_qs, unquote, urlparse

        want = unquote(parse_qs(urlparse(url).query).get("resolve_version", [""])[0])
        return _resolve_release_body(raw, want)

    html = await _fetch(url, cfg)
    if not html:
        return None
    return _extract_text(html)
