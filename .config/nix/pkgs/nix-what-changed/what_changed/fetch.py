from __future__ import annotations

import re
import subprocess
import urllib.request
from html.parser import HTMLParser


def _fetch(url: str, timeout: float = 8) -> str | None:
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except Exception:
        return None


def _raw_github(owner: str, repo: str, ref: str, path: str) -> str | None:
    url = f"https://raw.githubusercontent.com/{owner}/{repo}/{ref}/{path}"
    return _fetch(url)


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
        data = data[m.end() :]
    parser = _HTMLTextExtractor()
    parser.feed(data)
    result = "".join(parser.text)
    lines = [l.strip() for l in result.split("\n") if l.strip()]
    return "\n".join(lines) if lines else None


def _fetch_github_release(owner: str, repo: str, tag: str) -> str | None:
    try:
        result = subprocess.run(
            ["gh", "release", "view", tag, "--repo", f"{owner}/{repo}", "--json", "body", "--jq", ".body"],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    for path in ("ChangeLog", "NEWS", "CHANGES.md", "CHANGELOG.md", "RELEASE_NOTES.md", "NEWS.md"):
        content = _raw_github(owner, repo, tag, path)
        if content and re.search(r"(?i)change|fix|version|release|bug", content[:1000]):
            return content
    return None


def fetch_changelog(url: str) -> str | None:
    m = re.match(r"^https://github\.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)", url)
    if m:
        raw = _raw_github(m.group(1), m.group(2), m.group(3), m.group(4))
        return raw[:50000] if raw else None

    m = re.match(r"^https://github\.com/([^/]+)/([^/]+)/releases/tag/(.+)", url)
    if m:
        return _fetch_github_release(m.group(1), m.group(2), m.group(3))

    html = _fetch(url)
    if not html:
        return None
    text = _extract_text(html)
    return text
