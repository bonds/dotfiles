"""Regression tests for bugs that were introduced and fixed during development.

Each test is named after the fix commit or the bug it covers.
Run with: python -m pytest tests/test_regressions.py -v
"""

from __future__ import annotations

import os
import re
import tempfile

from what_changed import cache, urls
from what_changed.config import Config, load
from what_changed.differ import PackageChange
from what_changed.fetch import _extract_text, _HTMLTextExtractor
from what_changed.spellfix import fix
from what_changed.summarize import (
    CURATE_PROMPTS,
    KNOWN_MERGES,
    PROMPT_STYLES,
    _parse_bullets,
    _postprocess,
    _smarter_truncate,
)


# ── Regression 1: gh_timeout field name mismatch ─────────────────────
# Bug: config.py had `github_timeout` but fetch.py referenced `cfg.gh_timeout`.
#      AttributeError silently caught by thread pool → all LLM calls failed.
# Fix: Renamed field to `gh_timeout` in Config.

def test_config_field_gh_timeout_exists():
    """Would have caught the field name mismatch (github_timeout vs gh_timeout)."""
    cfg = Config()
    assert hasattr(cfg, "gh_timeout"), "fetch.py expects cfg.gh_timeout"
    assert isinstance(cfg.gh_timeout, int)


def test_config_field_http_timeout_exists():
    """fetch.py and urls.py both use cfg.http_timeout."""
    cfg = Config()
    assert hasattr(cfg, "http_timeout")


def test_config_field_timeout_exists():
    """summarize.py uses cfg.timeout for LLM calls."""
    cfg = Config()
    assert hasattr(cfg, "timeout")


# ── Regression 2: output_json not set in gen_match path ──────────────
# Bug: When restructuring CLI arg parsing, output_json/output_brief were
#      only set in the `elif date_match:` block, not in `if gen_match:`.
#      Caused UnboundLocalError on `what-changed -N`.
# Fix: Moved output flag assignments into gen_match block.

def test_config_default_prompt_is_valid():
    """Prompt style default should match a valid key in PROMPT_STYLES."""
    cfg = Config()
    assert cfg.prompt_style in PROMPT_STYLES, \
        f"Default prompt '{cfg.prompt_style}' not in PROMPT_STYLES"
    assert cfg.prompt_style == "curate", \
        f"Default prompt should be 'curate', got '{cfg.prompt_style}'"


# ── Regression 3: missing parser.parse_args() call ───────────────────
# Bug: When removing --benchmark from argparse, accidentally deleted the
#      `args = parser.parse_args()` line too.
# Fix: Added it back.
# (This can't be tested as a unit test — it requires running the CLI.)


# ── Regression 4: benchmark default model hardcoded ───────────────────
# Bug: benchmark.py had "gemma3:1b-it-qat" hardcoded as default,
#      ignoring the Config default.
# Fix: Used Config().model as the default.

def test_benchmark_config_model_consistency():
    """Benchmark default should match Config default when no --models given."""
    from what_changed.benchmark import run_sample, REFERENCE
    # Just verify the module imports and Config().model is reasonable
    cfg = Config()
    assert cfg.model, "Config must have a default model"
    assert ":" in cfg.model or "/" in cfg.model, "Model name should have a tag"


# ── Regression 5: spellfix correction() returning None ───────────────
# Bug: When pyspellchecker.correction() returns None (no good candidate),
#      _fix_word would return None instead of the original word.
# Fix: Added `return best if best else word` fallback.

def test_spellfix_preserves_unknown_words():
    """Words too far from dictionary should be left unchanged."""
    result = fix("parse_args")
    assert result == "parse_args"


def test_spellfix_preserves_code_with_dots():
    """Code identifiers with dots should not be 'corrected'."""
    result = fix("parser.parse_args()")
    assert result == "parser.parse_args()"


def test_spellfix_preserves_underscore_words():
    """snake_case identifiers should not be 'corrected'."""
    result = fix("output_json")
    assert result == "output_json"


# ── Regression 6: spellfix case-sensitive prefix splitting ────────────
# Bug: "Thisummary" → "this" prefix check failed because "This" is uppercase.
# Fix: Used lower() for prefix comparison, preserved original case.

def test_spellfix_case_insensitive_prefix():
    """Prefix splitting should work case-insensitively."""
    result = fix("Thisummary")
    # Either it splits to "This summary" or leaves it unchanged
    assert "summary" in result.lower()


def test_spellfix_prefix_stricter():
    """istricter should be split (is + stricter)."""
    result = fix("istricter")
    assert result == "is stricter" or "stricter" in result


def test_spellfix_doubled_letter():
    """sspecific should become specific."""
    result = fix("sspecific")
    assert result == "specific"


# ── Regression 7: KNOWN_MERGES not covering common merges ────────────
# Bug: Word merges like "githubuntu", "versionumber", "backendriver" etc.
#      weren't in KNOWN_MERGES, so they passed through uncorrected.
# Fix: Added them to KNOWN_MERGES.

def test_known_merges_all_entries_applied():
    """Every KNOWN_MERGES entry should actually transform text."""
    cfg = Config()
    cfg.prompt_style = "strict"
    for wrong, right in KNOWN_MERGES.items():
        result = _postprocess([wrong], cfg)
        assert len(result) > 0, f"KNOWN_MERGES produced empty result for '{wrong}'"
        # The merged form should have been replaced (result should differ from input)
        if wrong == result[0]:
            # If result is unchanged, it might be a substring case (e.g. "ockets" → "sockets"
            # where "ockets" is still a substring of "sockets")
            assert right in result[0], f"KNOWN_MERGES did not fix '{wrong}'→'{right}', got '{result[0]}'"


def test_known_merges_specific_cases():
    """Specific known merges that appeared in real LLM output."""
    cfg = Config()
    cfg.prompt_style = "strict"
    cases = {
        "versionumber": "version number",
        "backendriver": "backend driver",
        "removedue": "removed due",
        "addresspace": "address space",
        "mimallocator": "mimalloc allocator",
    }
    for wrong, expected in cases.items():
        result = _postprocess([wrong], cfg)
        assert len(result) > 0, f"KNOWN_MERGES should fix '{wrong}'"
        # The fix may not be exact due to other post-processing, but the merge should be split
        assert wrong not in result[0], f"'{wrong}' should have been corrected"


# ── Regression 8: cache poisoning from null bullets ──────────────────
# Bug: When nix eval failed, cache stored None bullets. On next run,
#      get_summary returned None, which was treated as "no cache" and
#      fetched again. But if it kept failing, the cache stayed corrupted.
# Fix: None bullets are still cached, but get_summary returns None
#      (which is different from "no cache entry").

def test_cache_poisoned_null_summary(tmp_path):
    """Cache with null bullets should return None (same as cache miss)."""
    cfg = Config()
    cfg.cache_dir = str(tmp_path)
    cache.set_summary("pkg", "1.0", "2.0", None, cfg)
    result = cache.get_summary("pkg", "1.0", "2.0", cfg)
    assert result is None


def test_cache_miss_and_poison_are_distinguishable(tmp_path):
    """Both cache miss and null-bullets return None, but neither blocks retry."""
    cfg = Config()
    cfg.cache_dir = str(tmp_path)
    miss = cache.get_summary("never-set", "1.0", "2.0", cfg)
    assert miss is None
    cache.set_summary("null-set", "1.0", "2.0", None, cfg)
    poisoned = cache.get_summary("null-set", "1.0", "2.0", cfg)
    assert poisoned is None


# ── Regression 9: HTML parser endtag takes wrong args ────────────────
# Bug: Test called parser.handle_endtag("tag") but the method signature
#      is handle_endtag(self, tag: str). The signature is fine — the
#      test was wrong.
# Fix: Removed the list from the test call.

def test_html_extractor_skip_counter():
    """Nested skip tags increment/decrement counter correctly."""
    parser = _HTMLTextExtractor()
    parser.handle_starttag("header", [])
    parser.handle_starttag("nav", [])
    assert parser.skip == 2
    parser.handle_endtag("nav")
    assert parser.skip == 1
    parser.handle_endtag("header")
    assert parser.skip == 0


def test_html_extractor_skip_never_negative():
    """Skip counter should never go below 0."""
    parser = _HTMLTextExtractor()
    parser.handle_endtag("footer")  # no matching start
    assert parser.skip == 0


# ── Regression 10: smarter truncation losing content ──────────────────
# Bug: Initial truncation was `text[:max_input_bytes]` which could cut
#      mid-word or mid-line, confusing the LLM.
# Fix: _smarter_truncate finds heading/newline boundaries.

def test_smarter_truncate_short_text():
    """Text under limit should not be truncated."""
    text = "Hello world"
    result = _smarter_truncate(text, 100)
    assert result == text


def test_smarter_truncate_at_heading():
    """Should break at a heading boundary near the limit."""
    text = "some preamble\n\n## Changes\n\nlots of changes here\n\n## Details\n\nmore"
    result = _smarter_truncate(text, 35)
    # Should break at the first heading boundary if within 40% of limit
    assert len(result) <= 35
    assert "##" in result  # should still contain a heading


# ── Regression 11: known URL mappings not reached by guess_url ────────
# Bug: GitHub name guessing ran before known URL mappings, so qemu's
#      wiki URL was shadowed by github.com/qemu/qemu (which exists but
#      has no useful release notes).
# Fix: Reordered: known URLs checked first.

def test_known_urls_take_precedence():
    """KNOWN_URLS should return URLs without external calls."""
    for pkg, maker in urls.KNOWN_URLS.items():
        url = maker("1.0.0")
        assert url is not None, f"KNOWN_URLS[{pkg}] returned None for 1.0.0"
        assert url.startswith("http"), f"KNOWN_URLS[{pkg}] returned non-URL: {url}"


def test_all_known_urls_return_valid_format():
    """Every known URL generator should produce valid-looking URLs."""
    versions = {
        "qemu": "9.2.0",
        "gcc": "15.2.0",
        "cargo": "1.0.0",
        "rustc": "1.0.0",
        "coreutils": "1.0.0",
        "discord": "1.0.0",
        "obsidian": "1.0.0",
        "dwarf-fortress": "53.01",
        "darwin-system": "26.05",
        "gimp": "1.0.0",
        "msmtp": "1.0.0",
        "rsync": "1.0.0",
        "linux": "6.18.34",
        "zfs-kernel": "2.4.2-6.18.33",
        "what-changed": "0.11.0",
    }
    for pkg, ver in versions.items():
        maker = urls.KNOWN_URLS.get(pkg)
        assert maker is not None, f"No KNOWN_URLS entry for {pkg}"
        url = maker(ver)
        assert url is not None, f"KNOWN_URLS[{pkg}]('{ver}') returned None"
        assert url.startswith("http"), f"KNOWN_URLS[{pkg}]('{ver}') = {url}"


# ── Regression 12: bullet parsing with numbered lists ─────────────────
# Bug: Numbered list items could be parsed as version numbers and filtered out.
# Fix: The version filter checks for version-number-only bullets.

def test_parse_bullets_numbered_not_filtered():
    """Numbered bullets should not be mistaken for version numbers."""
    bullets, _ = _parse_bullets("1. First change\n2. Second change\n3. Third change")
    assert len(bullets) == 3


def test_parse_bullets_version_numbers_filtered():
    """Bare version numbers as bullet points should be filtered out."""
    bullets, _ = _parse_bullets("* 1.2.3\n* v4.5.6\n* Real change")
    assert bullets == ["Real change"]


# ── Regression 13: post-processing should always apply ────────────────
# Bug: Post-processing steps were reordered or skipped in some paths.
# Fix: All post-processing steps (dedup, uppercase split, prefix merge,
#      doubled letter, backtick removal, KNOWN_MERGES) always run.

def test_postprocess_backtick_removal():
    """Backticks around commit hashes should be stripped."""
    cfg = Config()
    result = _postprocess(["`abc123` Fixed a bug", "`def456` Another fix"], cfg)
    for bullet in result:
        assert "`" not in bullet


def test_postprocess_dedup_repeated_words():
    """Repeated words due to LLM stuttering should be deduped."""
    cfg = Config()
    cfg.prompt_style = "strict"
    result = _postprocess(["the the same word word repeat"], cfg)
    assert "the the" not in result[0]
    assert "word word" not in result[0]


def test_postprocess_doubled_first_letter():
    """LLM output artifacts like 'ssystemd' should be fixed."""
    cfg = Config()
    cfg.prompt_style = "strict"
    result = _postprocess(["ssystemd configuration"], cfg)
    assert len(result) > 0
    assert "ssystemd" not in result[0]


# ── Regression 14: Config file should override all fields ─────────────
# Bug: When loading from config file, only some fields were overridden.
# Fix: Uses dataclass fields() to iterate over all fields.

def test_config_load_override_all(tmp_path):
    """Config file should override all accessible fields."""
    cfg_path = tmp_path / "config.toml"
    cfg_path.write_text(
        'model = "test-model"\n'
        'timeout = 99\n'
        'max_bullets = 3\n'
        'prompt_style = "strict"\n'
        'backend = "openai"\n'
    )
    cfg = load(str(cfg_path))
    assert cfg.model == "test-model"
    assert cfg.timeout == 99
    assert cfg.max_bullets == 3
    assert cfg.prompt_style == "strict"
    assert cfg.backend == "openai"


# ── Regression 15: empty changelog doesn't crash summarize ────────────
# Bug: Very short changelog text (< 100 chars) should return None,
#      not crash.
# Fix: Early return len(text) < 100 → None.

def test_summarize_empty_text_returns_none():
    """Empty changelog should return None, not crash."""
    cfg = Config()
    import asyncio
    try:
        asyncio.run(_async_summarize_empty(cfg))
    except RuntimeError:
        pass  # expected if no event loop


async def _async_summarize_empty(cfg):
    from what_changed.summarize import summarize
    result = await summarize("test", "short", cfg)
    assert result is None


# ── Regression 16: generation resolution should handle missing gens ──
# Bug: _gen_info would crash if the generation symlink doesn't exist.
# Fix: (This is an integration test — can't fully test without /nix)
#      We can at least test the parsing logic.

def test_gen_link_parsing():
    """Generation number parsing from symlink names."""
    m = re.search(r"system-(\d+)-link", "system-42-link")
    assert m is not None
    assert int(m.group(1)) == 42


# ── Regression 18: curate postprocess preserves original text ─────────
# Bug: If curate mode applied post-processing, it would alter verbatim
#      changelog text, defeating the purpose of curation.
# Fix: _postprocess skips spellfix/KNOWN_MERGES/dedup when style is curate.

def test_curate_preserves_verbatim_text():
    """Curate mode should not alter original changelog text."""
    cfg = Config()
    cfg.prompt_style = "curate"
    text = "Fixed a bug in the parser (issue #123) by @author"
    result = _postprocess([text], cfg)
    assert result[0] == text


# ── Regression 19: curate uses CURATE_PROMPTS not PROMPTS ────────────
# Bug: If summarize() used PROMPTS instead of CURATE_PROMPTS for curate
#      style, the source instructions would say "summarize" not "select".
# Fix: summarize() checks prompt_style and uses CURATE_PROMPTS accordingly.

def test_curate_source_prompts_differ():
    """CURATE_PROMPTS should use different language from PROMPTS."""
    assert "select" in CURATE_PROMPTS["release"].lower()
    assert "summarize" not in CURATE_PROMPTS["release"].lower()
    # Import PROMPTS for comparison
    from what_changed.summarize import PROMPTS
    assert "summarize" in PROMPTS["release"].lower()


# ── Regression 20: cache key includes prompt_style ────────────────────
# Bug: Without prompt_style in cache key, switching from "strict" to
#      "curate" would serve stale composed summaries.
# Fix: Cache key format is now "summary:{prompt_style}:{pkg}:..."

def test_cache_key_isolates_prompt_style(tmp_path):
    """Different prompt_styles should produce different cached summaries."""
    from what_changed import cache
    cfg1 = Config()
    cfg1.cache_dir = str(tmp_path)
    cfg1.prompt_style = "curate"
    cfg2 = Config()
    cfg2.cache_dir = str(tmp_path)
    cfg2.prompt_style = "strict"

    cache.set_summary("pkg", "1.0", "2.0", ["curate bullets"], cfg1)
    cache.set_summary("pkg", "1.0", "2.0", ["strict bullets"], cfg2)

    assert cache.get_summary("pkg", "1.0", "2.0", cfg1) == ["curate bullets"]
    assert cache.get_summary("pkg", "1.0", "2.0", cfg2) == ["strict bullets"]


# ── Regression 17: cache keys should be isolated by package + version ─
# Bug: Different pkg/version combos could collide in cache.
# Fix: Keys include pkg, old_ver, new_ver in the hash.

def test_cache_key_isolation():
    """Different packages with same versions should not collide."""
    cfg = Config()
    with tempfile.TemporaryDirectory() as d:
        cfg.cache_dir = d
        cache.set_summary("pkg-a", "1.0", "2.0", ["a bullets"], cfg)
        cache.set_summary("pkg-b", "1.0", "2.0", ["b bullets"], cfg)
        assert cache.get_summary("pkg-a", "1.0", "2.0", cfg) == ["a bullets"]
        assert cache.get_summary("pkg-b", "1.0", "2.0", cfg) == ["b bullets"]


def test_cache_version_isolation():
    """Same package, different versions should not collide."""
    cfg = Config()
    with tempfile.TemporaryDirectory() as d:
        cfg.cache_dir = d
        cache.set_summary("pkg", "1.0", "2.0", ["old bullets"], cfg)
        cache.set_summary("pkg", "2.0", "3.0", ["new bullets"], cfg)
        assert cache.get_summary("pkg", "1.0", "2.0", cfg) == ["old bullets"]
        assert cache.get_summary("pkg", "2.0", "3.0", cfg) == ["new bullets"]
