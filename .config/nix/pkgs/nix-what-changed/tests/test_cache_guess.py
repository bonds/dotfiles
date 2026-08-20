from __future__ import annotations

import asyncio
import time

import pytest

from what_changed import cache, cli, urls
from what_changed.config import Config


def _run(coro):
    return asyncio.run(coro)


def _cfg(tmp_path):
    cfg = Config()
    cfg.cache_dir = str(tmp_path)
    return cfg


def test_fresh_cached_url_reused(monkeypatch, tmp_path):
    """A fresh, valid cached guessed URL should be reused without re-guessing."""
    cfg = _cfg(tmp_path)
    info = {"guessed_url": "https://example.com/CHANGELOG.md", "guessed_at": int(time.time())}

    monkeypatch.setattr(cli, "no_cache", False)
    monkeypatch.setattr(urls, "_http_ok", lambda *a, **k: _ok(True))
    calls = {"guess": 0}

    async def fake_guess(*a, **k):
        calls["guess"] += 1
        return "REGUESSED"

    monkeypatch.setattr(urls, "guess_url", fake_guess)

    url, out_info = _run(cli._resolve_or_guess("foo", "1.0", dict(info), cfg))
    assert url == "https://example.com/CHANGELOG.md"
    assert calls["guess"] == 0
    assert out_info["guessed_url"] == info["guessed_url"]


def test_fresh_dead_url_re_guesses_and_invalidates(monkeypatch, tmp_path):
    """A fresh cached URL that 404s should be dropped and re-guessed."""
    cfg = _cfg(tmp_path)
    info = {"guessed_url": "https://example.com/dead", "guessed_at": int(time.time())}

    monkeypatch.setattr(cli, "no_cache", False)
    monkeypatch.setattr(urls, "_http_ok", lambda *a, **k: _ok(False))
    monkeypatch.setattr(cache, "invalidate_metadata_guess", lambda *a, **k: None)

    # Pre-seed the cache so the invalidation path has something to work on.
    cache.set_metadata("foo", dict(info), cfg)

    calls = {"guess": 0}

    async def fake_guess(*a, **k):
        calls["guess"] += 1
        return "NEW_URL"

    monkeypatch.setattr(urls, "guess_url", fake_guess)

    url, out_info = _run(cli._resolve_or_guess("foo", "1.0", dict(info), cfg))
    assert url == "NEW_URL"
    assert calls["guess"] == 1
    # the new guess replaces the dead one in the returned info
    assert out_info["guessed_url"] == "NEW_URL"


def test_fresh_none_cached_skips_guess(monkeypatch, tmp_path):
    """A fresh cached 'no changelog found' result should be trusted, not re-searched."""
    cfg = _cfg(tmp_path)
    info = {"guessed_url": None, "guessed_at": int(time.time())}

    monkeypatch.setattr(cli, "no_cache", False)

    async def fake_guess(*a, **k):
        raise AssertionError("should not re-guess fresh None")

    monkeypatch.setattr(urls, "guess_url", fake_guess)

    url, out_info = _run(cli._resolve_or_guess("foo", "1.0", dict(info), cfg))
    assert url is None
    assert out_info["guessed_url"] is None


def test_fresh_none_with_known_url_re_guesses(monkeypatch, tmp_path):
    """A fresh cached 'no changelog' must not suppress a known URL mapping.

    KNOWN_URLS are resolved without network, so once a mapping exists for a
    package, always use it even if 'None' was cached fresh (so new mappings
    take effect without waiting out the TTL).
    """
    cfg = _cfg(tmp_path)
    info = {"guessed_url": None, "guessed_at": int(time.time())}

    monkeypatch.setattr(cli, "no_cache", False)
    monkeypatch.setattr(urls, "KNOWN_URLS", {"glib": lambda v: "https://gitlab.gnome.org/GNOME/glib/-/raw/main/NEWS"})

    async def fake_guess(*a, **k):
        return urls.KNOWN_URLS["glib"]("2.88.3")

    monkeypatch.setattr(urls, "guess_url", fake_guess)

    url, out_info = _run(cli._resolve_or_guess("glib", "2.88.3", dict(info), cfg))
    assert url == "https://gitlab.gnome.org/GNOME/glib/-/raw/main/NEWS"
    assert out_info["guessed_url"] == url


def test_stale_cached_re_guesses(monkeypatch, tmp_path):
    """A stale cached guess (expired TTL) should trigger a re-guess."""
    cfg = _cfg(tmp_path)
    stale = int(time.time()) - cache.GUESS_TTL - 10
    info = {"guessed_url": "https://example.com/old", "guessed_at": stale}

    monkeypatch.setattr(cli, "no_cache", False)
    monkeypatch.setattr(urls, "_http_ok", lambda *a, **k: _ok(True))

    async def fake_guess(*a, **k):
        return "REFRESHED_URL"

    monkeypatch.setattr(urls, "guess_url", fake_guess)

    url, _ = _run(cli._resolve_or_guess("foo", "1.0", dict(info), cfg))
    assert url == "REFRESHED_URL"


def test_guess_result_is_cached(monkeypatch, tmp_path):
    """A fresh guess should be written back to the metadata cache with a timestamp."""
    cfg = _cfg(tmp_path)
    info = {}

    monkeypatch.setattr(cli, "no_cache", False)

    async def fake_guess(*a, **k):
        return "https://example.com/new"

    monkeypatch.setattr(urls, "guess_url", fake_guess)

    url, out_info = _run(cli._resolve_or_guess("foo", "1.0", dict(info), cfg))
    assert url == "https://example.com/new"
    assert out_info["guessed_url"] == "https://example.com/new"
    assert isinstance(out_info["guessed_at"], int)


def test_version_returns_string():
    """_version() should always return a non-empty string (real or fallback)."""
    assert isinstance(cli._version(), str)
    assert cli._version().strip() != ""


def test_version_flag_prints_program_name():
    """what-changed --version should print 'what-changed <version>' and exit 0."""
    import argparse
    import contextlib
    import io

    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--version", action="version",
                        version=f"what-changed {cli._version()}")
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf), pytest.raises(SystemExit) as exc:
        parser.parse_args(["--version"])
    assert exc.value.code == 0
    out = buf.getvalue().strip()
    assert out.startswith("what-changed ")
    assert out != "what-changed "


def _ok(ok: bool):
    async def _inner(*a, **k):
        return ok

    return _inner()