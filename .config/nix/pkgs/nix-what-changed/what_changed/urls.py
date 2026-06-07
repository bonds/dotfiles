from __future__ import annotations

import re
import urllib.request
from collections.abc import Callable

from what_changed import metadata


def _http_ok(url: str, timeout: float = 4) -> bool:
    try:
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return 200 <= resp.status < 300
    except Exception:
        return False


def _guess_from_homepage(pkg: str, homepage: str | None, new_ver: str) -> str | None:
    if not homepage:
        return None
    m = re.match(r"^https://github\.com/([^/]+)/([^/]+)/?$", homepage)
    if not m:
        return None
    owner, repo = m.group(1), m.group(2)
    gh_url = f"https://github.com/{owner}/{repo}"
    for tag in (f"v{new_ver}", new_ver, f"{pkg}-{new_ver}"):
        url = f"{gh_url}/releases/tag/{tag}"
        if _http_ok(url):
            return url
    for path in ("CHANGELOG.md", "CHANGES.md", "RELEASE_NOTES.md", "NEWS.md", "ChangeLog", "CHANGELOG", "NEWS"):
        url = f"{gh_url}/blob/main/{path}"
        if _http_ok(url):
            return url
    return None


def _guess_from_name(pkg: str, new_ver: str) -> str | None:
    for guess in (f"{pkg}/{pkg}", f"{pkg}-users/{pkg}", f"{pkg}-engine/{pkg}"):
        gh_url = f"https://github.com/{guess}"
        for tag in (f"v{new_ver}", new_ver, f"{pkg}-{new_ver}"):
            url = f"{gh_url}/releases/tag/{tag}"
            if _http_ok(url):
                return url
        for path in ("CHANGELOG.md", "CHANGES.md", "RELEASE_NOTES.md", "NEWS.md", "ChangeLog", "CHANGELOG", "NEWS"):
            url = f"{gh_url}/blob/main/{path}"
            if _http_ok(url):
                return url
    return None


KNOWN_URLS: dict[str, Callable[[str], str | None]] = {}


def _make_qemu_url(new_ver: str) -> str | None:
    parts = new_ver.split(".")
    if len(parts) >= 2:
        return f"https://wiki.qemu.org/ChangeLog/{parts[0]}.{parts[1]}"
    return None


KNOWN_URLS["qemu"] = _make_qemu_url


def guess_url(pkg: str, new_ver: str) -> str | None:
    if pkg in KNOWN_URLS:
        url = KNOWN_URLS[pkg](new_ver)
        if url:
            return url
    changelog_url = None
    homepage = metadata.get_homepage(pkg)
    if homepage:
        changelog_url = _guess_from_homepage(pkg, homepage, new_ver)
    if not changelog_url:
        changelog_url = _guess_from_name(pkg, new_ver)
    return changelog_url
