from __future__ import annotations

import re
from collections.abc import Callable

import httpx

from what_changed import metadata
from what_changed.config import Config


def __getattr__(name):
    """Lazy import workaround for module-level httpx client."""
    raise AttributeError(name)


async def _http_ok(url: str, cfg: Config) -> bool:
    for attempt in range(2):
        try:
            async with httpx.AsyncClient(timeout=cfg.http_timeout, follow_redirects=True) as c:
                resp = await c.head(url)
                return 200 <= resp.status_code < 300
        except Exception:
            if attempt < 1:
                await __import__("asyncio").sleep(1)
            else:
                return False
    return False


async def _guess_from_homepage(pkg: str, homepage: str | None, new_ver: str, cfg: Config) -> str | None:
    if not homepage:
        return None
    m = re.match(r"^https://github\.com/([^/]+)/([^/]+)/?$", homepage)
    if not m:
        return None
    owner, repo = m.group(1), m.group(2)
    gh_url = f"https://github.com/{owner}/{repo}"
    for tag in (f"v{new_ver}", new_ver, f"{pkg}-{new_ver}"):
        url = f"{gh_url}/releases/tag/{tag}"
        if await _http_ok(url, cfg):
            return url
    for path in ("CHANGELOG.md", "CHANGES.md", "RELEASE_NOTES.md", "NEWS.md", "ChangeLog", "CHANGELOG", "NEWS"):
        url = f"{gh_url}/blob/main/{path}"
        if await _http_ok(url, cfg):
            return url
    return None


async def _guess_from_name(pkg: str, new_ver: str, cfg: Config) -> str | None:
    for guess in (f"{pkg}/{pkg}", f"{pkg}-users/{pkg}", f"{pkg}-engine/{pkg}"):
        gh_url = f"https://github.com/{guess}"
        for tag in (f"v{new_ver}", new_ver, f"{pkg}-{new_ver}"):
            url = f"{gh_url}/releases/tag/{tag}"
            if await _http_ok(url, cfg):
                return url
        for path in ("CHANGELOG.md", "CHANGES.md", "RELEASE_NOTES.md", "NEWS.md", "ChangeLog", "CHANGELOG", "NEWS"):
            url = f"{gh_url}/blob/main/{path}"
            if await _http_ok(url, cfg):
                return url
    return None


KNOWN_URLS: dict[str, Callable[[str], str | None]] = {}


def _make_qemu_url(new_ver: str) -> str | None:
    parts = new_ver.split(".")
    if len(parts) >= 2:
        return f"https://wiki.qemu.org/ChangeLog/{parts[0]}.{parts[1]}"
    return None


KNOWN_URLS["qemu"] = _make_qemu_url


def _make_darwin_system_url(new_ver: str) -> str | None:
    parts = new_ver.split(".")
    if len(parts) < 2:
        return None
    ver_no_dot = parts[0] + parts[1].zfill(2)
    return (
        f"https://raw.githubusercontent.com/NixOS/nixpkgs/nixpkgs-unstable/"
        f"nixos/doc/manual/release-notes/rl-{ver_no_dot}.section.md"
    )


KNOWN_URLS["darwin-system"] = _make_darwin_system_url


def _make_gcc_url(new_ver: str) -> str | None:
    parts = new_ver.split(".")
    if len(parts) >= 1:
        return f"https://gcc.gnu.org/gcc-{parts[0]}/changes.html"
    return None


KNOWN_URLS["gcc"] = _make_gcc_url


def _make_what_changed_url(new_ver: str) -> str | None:
    return "https://api.github.com/repos/bonds/dotfiles/commits?path=.config/nix/pkgs/nix-what-changed&per_page=10"


KNOWN_URLS["what-changed"] = _make_what_changed_url


def _make_github_blob(owner: str, repo: str, path: str, ref: str = "master"):
    def make(new_ver: str) -> str:
        return f"https://github.com/{owner}/{repo}/blob/{ref}/{path}"
    return make


KNOWN_URLS["cargo"] = _make_github_blob("rust-lang", "cargo", "CHANGELOG.md")
KNOWN_URLS["rustc"] = _make_github_blob("rust-lang", "rust", "RELEASES.md")
KNOWN_URLS["coreutils"] = _make_github_blob("coreutils", "coreutils", "NEWS")
KNOWN_URLS["msmtp"] = _make_github_blob("marlam", "msmtp", "NEWS")
KNOWN_URLS["rsync"] = _make_github_blob("WayneD", "rsync", "NEWS.md")


def _make_gimp_url(new_ver: str) -> str | None:
    return "https://gitlab.gnome.org/GNOME/gimp/-/raw/master/NEWS"


KNOWN_URLS["gimp"] = _make_gimp_url


def _make_obsidian_url(new_ver: str) -> str | None:
    return "https://obsidian.md/changelog/"


KNOWN_URLS["obsidian"] = _make_obsidian_url


def _make_discord_url(new_ver: str) -> str | None:
    return "https://discord.com/tags/changelog"


KNOWN_URLS["discord"] = _make_discord_url


def _make_dwarf_fortress_url(new_ver: str) -> str | None:
    return "https://dwarffortresswiki.org/index.php/Version_history"


KNOWN_URLS["dwarf-fortress"] = _make_dwarf_fortress_url


async def patch_release_tag(url: str, new_ver: str, cfg: Config) -> str:
    m = re.match(r"(https://github\.com/[^/]+/[^/]+/releases/tag/)(.*)", url)
    if not m:
        return url
    base, tag = m.group(1), m.group(2)
    tag_ver = re.sub(r"^v", "", tag)
    if tag_ver == new_ver:
        return url
    for fmt in (f"v{new_ver}", new_ver, f"unknown-{new_ver}"):
        new_url = f"{base}{fmt}"
        if await _http_ok(new_url, cfg):
            return new_url
    return url


async def guess_url(pkg: str, new_ver: str, cfg: Config) -> str | None:
    if pkg in KNOWN_URLS:
        url = KNOWN_URLS[pkg](new_ver)
        if url:
            return url
    homepage = metadata.get_homepage(pkg)
    if homepage:
        url = await _guess_from_homepage(pkg, homepage, new_ver, cfg)
        if url:
            return url
    return await _guess_from_name(pkg, new_ver, cfg)
