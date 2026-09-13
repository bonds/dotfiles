from what_changed import summarize
from what_changed.config import Config


def test_parse_bullets_star():
    text = "* First change\n* Second change\n* Third change"
    bullets, non = summarize._parse_bullets(text)
    assert bullets == ["First change", "Second change", "Third change"]
    assert non == []


def test_parse_bullets_dash():
    text = "- Item one\n- Item two"
    bullets, non = summarize._parse_bullets(text)
    assert bullets == ["Item one", "Item two"]


def test_parse_bullets_numbered():
    text = "1. First\n2. Second"
    bullets, non = summarize._parse_bullets(text)
    assert bullets == ["First", "Second"]


def test_parse_bullets_mixed_preamble():
    text = "Here are the changes:\n* First\n* Second"
    bullets, non = summarize._parse_bullets(text)
    assert bullets == ["First", "Second"]
    assert non == ["Here are the changes:"]


def test_parse_bullets_continuation():
    text = "* First line\n  continued\n* Second"
    bullets, non = summarize._parse_bullets(text)
    assert bullets == ["First line continued", "Second"]


def test_parse_bullets_skips_urls():
    text = "* A change\nhttps://example.com\n* Another"
    bullets, non = summarize._parse_bullets(text)
    assert bullets == ["A change", "Another"]


def test_parse_bullets_filters_version_numbers():
    text = "* 1.2.3\n*  v4.5.6 \n* Real change"
    bullets, non = summarize._parse_bullets(text)
    assert bullets == ["Real change"]


def test_parse_bullets_bold_removal():
    text = "* **Important** fix\n* **Another** item"
    bullets, non = summarize._parse_bullets(text)
    assert bullets == ["Important fix", "Another item"]


def test_postprocess_dedup():
    cfg = Config()
    cfg.prompt_style = "strict"
    result = summarize._postprocess(["the the same", "word word repeat"], cfg)
    assert result == ["the same", "word repeat"]


def test_postprocess_word_merge():
    cfg = Config()
    cfg.prompt_style = "default"
    result = summarize._postprocess(["forMathe", "theXcerpt"], cfg)
    # Upper-case splits applied, then spellfix may further correct
    assert len(result) > 0


def test_summarize_short_text_returns_none():
    cfg = Config()
    result = summarize._parse_bullets("")
    assert result == ([], [])


# ── Curate mode tests ─────────────────────────────────────────────────


def test_curate_prompt_style_exists():
    """Curate prompt style should be a valid key in PROMPT_STYLES."""
    assert "curate" in summarize.PROMPT_STYLES


def test_curate_uses_curate_prompts():
    """When prompt_style is curate, CURATE_PROMPTS should be used for source prompts."""
    cfg = Config()
    cfg.prompt_style = "curate"
    # CURATE_PROMPTS should exist and have all the same keys as PROMPTS
    assert hasattr(summarize, "CURATE_PROMPTS")
    assert set(summarize.CURATE_PROMPTS.keys()) == set(summarize.PROMPTS.keys())


def test_curate_postprocess_skips_heavy_fixups():
    """Curate mode post-processing should skip spellfix/KNOWN_MERGES etc."""
    cfg = Config()
    cfg.prompt_style = "curate"
    # Verbatim text with known merge artifacts should pass through unchanged
    text = "this has versionumber and sspecific artifacts"
    result = summarize._postprocess([text], cfg)
    assert len(result) > 0
    # The artifacts should remain unchanged since curate mode doesn't fix them
    assert "versionumber" in result[0]
    assert "sspecific" in result[0]


def test_curate_postprocess_removes_backticks():
    """Curate mode should still remove backticks."""
    cfg = Config()
    cfg.prompt_style = "curate"
    result = summarize._postprocess(["`abc123` Fixed a bug"], cfg)
    assert "`" not in result[0]


def test_non_curate_postprocess_still_fixes():
    """Non-curate prompt styles should still get full post-processing."""
    cfg = Config()
    cfg.prompt_style = "strict"
    # spellfix + KNOWN_MERGES should still apply
    result = summarize._postprocess(["ssystemd configuration"], cfg)
    assert "ssystemd" not in result[0]
    assert result[0]


# ── Version-range trimming tests ──────────────────────────────────────────
# Whole-file changelogs (CHANGELOG.md, NEWS, RELEASES.md, HISTORY.rst) list
# every release newest-first.  These tests pin down _find_section /
# _slice_version_range so older releases' entries never reach the LLM.


def test_find_section_markdown_heading():
    text = (
        "## v3.44.1\n"
        "- Fix bug A\n"
        "- Add feature B\n"
        "\n"
        "## v3.43.0\n"
        "- Old change\n"
    )
    start, strength = summarize._find_section(text, "3.44.1")
    assert start == 0
    assert strength == 2
    start, strength = summarize._find_section(text, "3.43.0")
    assert strength == 2
    assert text[start:].startswith("## v3.43.0")


def test_find_section_rst_underline():
    text = (
        "Version 1.98.1 (2026-09-03)\n"
        "===========================\n"
        "\n"
        "* fix miscompilation\n"
        "\n"
        "Version 1.98.0 (2026-08-20)\n"
        "===========================\n"
        "\n"
        "Language\n"
        "--------\n"
        "- some change\n"
    )
    start, strength = summarize._find_section(text, "1.98.1")
    assert strength == 2
    assert text[start:].startswith("Version 1.98.1")
    start, strength = summarize._find_section(text, "1.98.0")
    assert strength == 2
    assert text[start:].startswith("Version 1.98.0")


def test_find_section_prefix_version_does_not_collide():
    # "1.98" must not match the longer "1.98.0" / "1.98.1" sections
    text = "Version 1.98.0 (2026-08-20)\n===========================\n"
    assert summarize._find_section(text, "1.98") == (None, 0)


def test_find_section_bare_version_is_weak():
    text = "0.4.0\nSome body line without a version header.\n"
    start, strength = summarize._find_section(text, "0.4.0")
    assert strength == 1
    assert start == 0


def test_find_section_body_text_not_header():
    text = "Update to v0.4.0 of the Brotli library.\nMore details here.\n"
    assert summarize._find_section(text, "0.4.0") == (None, 0)


def test_slice_version_range_markdown_keeps_only_new():
    text = (
        "## v3.44.1\n"
        "- New fix for the new version\n"
        "\n"
        "## v3.43.0\n"
        "- Old change from the previous version\n"
        "\n"
        "## v3.42.0\n"
        "- Ancient change\n"
    )
    sliced = summarize._slice_version_range(text, "3.43.0", "3.44.1")
    assert sliced.startswith("## v3.44.1")
    assert "New fix for the new version" in sliced
    assert "Old change from the previous version" not in sliced
    assert "Ancient change" not in sliced


def test_slice_version_range_rst_style():
    text = (
        "Version 1.98.1 (2026-09-03)\n"
        "===========================\n"
        "\n"
        "* fix miscompilation in vtables\n"
        "\n"
        "Version 1.98.0 (2026-08-20)\n"
        "===========================\n"
        "\n"
        "Language\n"
        "--------\n"
        "- shorten lifetimes\n"
    )
    sliced = summarize._slice_version_range(text, "1.98.0", "1.98.1")
    assert "Version 1.98.1" in sliced
    assert "fix miscompilation in vtables" in sliced
    assert "Version 1.98.0" not in sliced
    assert "shorten lifetimes" not in sliced


def test_slice_version_range_old_above_new_keeps_new_down():
    # unusual ordering (old listed above new) keeps the new section downward
    text = (
        "Version 3.43.0 (2025-12-01)\n"
        "============================\n"
        "old change\n"
        "Version 3.44.1 (2026-01-15)\n"
        "============================\n"
        "new change\n"
    )
    sliced = summarize._slice_version_range(text, "3.43.0", "3.44.1")
    assert "new change" in sliced
    assert "old change" not in sliced


def test_slice_version_range_no_headers_unchanged():
    text = "Just some prose with no version sections.\nAnother line.\n"
    assert summarize._slice_version_range(text, "3.43.0", "3.44.1") == text


def test_slice_version_range_weak_headers_slice_when_both_found():
    # bare-version lines (strength 1) now slice when both markers are found —
    # that's how obsidian-style changelogs ("1.14.1" on its own line) are scoped
    text = "3.44.1\nSome new change here.\n3.43.0\nSome old change.\n"
    sliced = summarize._slice_version_range(text, "3.43.0", "3.44.1")
    assert "3.44.1" in sliced
    assert "new change" in sliced
    assert "3.43.0" not in sliced
    assert "old change" not in sliced


def test_slice_version_range_single_weak_found_unchanged():
    # a lone bare-version line isn't enough to trigger trimming
    text = "3.44.1\nSome new change here.\n"
    assert summarize._slice_version_range(text, "3.43.0", "3.44.1") == text


def test_slice_version_range_obsidian_style():
    text = (
        "September 8, 2026\n"
        "1.14.1\n"
        "- Fixed the thing users noticed\n"
        "\n"
        "September 2, 2026\n"
        "1.14.0\n"
        "- Old change from the previous release\n"
        "\n"
        "August 20, 2026\n"
        "1.13.8\n"
        "- Ancient change\n"
    )
    sliced = summarize._slice_version_range(text, "1.14.0", "1.14.1")
    assert "1.14.1" in sliced
    assert "Fixed the thing users noticed" in sliced
    assert "1.14.0" not in sliced
    assert "Ancient change" not in sliced


def test_slice_version_range_missing_versions_unchanged():
    text = "## v3.44.1\n- change\n"
    assert summarize._slice_version_range(text, None, "3.44.1") == text
    assert summarize._slice_version_range(text, "3.43.0", None) == text
    assert summarize._slice_version_range(text, "3.44.1", "3.44.1") == text


def test_summarize_prompt_names_version_range():
    """The prompt must name old→new and the old section must be sliced out."""
    import asyncio
    from unittest.mock import patch

    cfg = Config()
    cfg.backend = "openai"
    text = (
        "## v3.44.1\n"
        "- Fixed the thing users noticed in this new release\n"
        "- Added the long-awaited feature flag toggle option\n"
        "- Resolved several issues that affected performance in bulk operations\n"
        "\n"
        "## v3.43.0\n"
        "- Old change that should be ignored entirely\n"
    )
    captured = {}

    async def fake_call(prompt, cfg):
        captured["prompt"] = prompt
        return "- Fixed the thing users noticed in this new release"

    with patch("what_changed.summarize._call_llm", side_effect=fake_call):
        bullets = asyncio.run(summarize.summarize(
            "slack-sdk", text, cfg, old_version="3.43.0", new_version="3.44.1"
        ))

    assert bullets
    assert "3.44.1" in captured["prompt"]
    assert "3.43.0" in captured["prompt"]
    assert "Old change that should be ignored entirely" not in captured["prompt"]


def test_summarize_without_versions_has_no_range_hint():
    import asyncio
    from unittest.mock import patch

    cfg = Config()
    cfg.backend = "openai"
    text = (
        "## v3.44.1\n"
        "- Fixed the thing users noticed in this new release\n"
        "- Added the long-awaited feature flag toggle option\n"
        "- Resolved several issues that affected performance in bulk operations\n"
    )
    captured = {}

    async def fake_call(prompt, cfg):
        captured["prompt"] = prompt
        return "- Some change"

    with patch("what_changed.summarize._call_llm", side_effect=fake_call):
        asyncio.run(summarize.summarize("slack-sdk", text, cfg))

    assert "compared to the previous version" not in captured["prompt"]


# ── Commit-feed trimming tests ────────────────────────────────────────────
# what-changed / polyptych point their own changelog at a GitHub commits API
# feed (no version sections — the version lives in the commit subject).  These
# tests pin down the marker-based slicing for that source type.


def test_looks_like_commit_feed():
    feed = (
        "17e5fdd what-changed: trim summaries to the window (v0.21.3)\n"
        "e2f6d15 what-changed: fix blank changelogs for python3 (v0.21.2)\n"
    )
    assert summarize._looks_like_commit_feed(feed)
    assert not summarize._looks_like_commit_feed("## v3.44.1\n- change\n")
    assert not summarize._looks_like_commit_feed("")


def test_slice_commit_feed_keeps_only_new_version():
    feed = (
        "17e5fdd what-changed: trim summaries to the old->new window (v0.21.3)\n"
        "e2f6d15 what-changed: fix blank changelogs for python3Packages (v0.21.2)\n"
        "98ed03c what-changed: add changelog resolution (v0.21.0)\n"
        "b034d18 what-changed: add docker mapping, bump to 0.17.0\n"
    )
    sliced = summarize._slice_commit_feed(feed, "0.21.2", "0.21.3")
    assert "17e5fdd" in sliced
    assert "trim summaries" in sliced
    assert "e2f6d15" not in sliced
    assert "98ed03c" not in sliced
    assert "b034d18" not in sliced


def test_slice_commit_feed_keeps_unmarked_commits_between_markers():
    # an unmarked commit between the new-version bump and the previous version
    # marker belongs to the new release and stays
    feed = (
        "17e5fdd what-changed: trim summaries (v0.21.3)\n"
        "9a1b2c3 what-changed: fix a follow-up typo\n"
        "e2f6d15 what-changed: fix blank changelogs (v0.21.2)\n"
    )
    sliced = summarize._slice_commit_feed(feed, "0.21.2", "0.21.3")
    assert "17e5fdd" in sliced
    assert "9a1b2c3" in sliced
    assert "e2f6d15" not in sliced


def test_slice_commit_feed_only_old_marker_keeps_above():
    feed = (
        "17e5fdd what-changed: trim summaries (v0.21.3)\n"
        "ac5a288 what-changed: fix hermes-agent changelog\n"
        "e2f6d15 what-changed: fix blank changelogs (v0.21.2)\n"
    )
    sliced = summarize._slice_commit_feed(feed, "0.21.2", "9.9.9")
    assert "17e5fdd" in sliced
    assert "ac5a288" in sliced
    assert "e2f6d15" not in sliced


def test_slice_commit_feed_no_markers_unchanged():
    feed = "17e5fdd some commit without a version marker\nac5a288 another commit\n"
    assert summarize._slice_commit_feed(feed, "0.21.2", "0.21.3") == feed


def test_slice_commit_feed_missing_versions_unchanged():
    feed = "17e5fdd what-changed: trim summaries (v0.21.3)\n"
    assert summarize._slice_commit_feed(feed, None, "0.21.3") == feed
    assert summarize._slice_commit_feed(feed, "0.21.2", None) == feed


def test_summarize_commit_feed_scoped_in_prompt():
    """The old version's commit must be sliced out of the prompt."""
    import asyncio
    from unittest.mock import patch

    cfg = Config()
    cfg.backend = "openai"
    feed = (
        "17e5fdd what-changed: trim summaries to the old->new window (v0.21.3)\n"
        "e2f6d15 what-changed: fix blank changelogs for python3Packages (v0.21.2)\n"
        "98ed03c what-changed: add changelog resolution for brotlicffi (v0.21.0)\n"
    )
    captured = {}

    async def fake_call(prompt, cfg):
        captured["prompt"] = prompt
        return "- trim summaries to the old->new window"

    with patch("what_changed.summarize._call_llm", side_effect=fake_call):
        bullets = asyncio.run(summarize.summarize(
            "what-changed", feed, cfg, old_version="0.21.2", new_version="0.21.3"
        ))

    assert bullets
    assert "17e5fdd" in captured["prompt"]
    assert "e2f6d15" not in captured["prompt"]
    assert "98ed03c" not in captured["prompt"]


def test_version_scope_instruction_keeps_original_tags():
    inst = summarize._version_scope_instruction("0.21.2", "0.21.5")
    assert "Summarize ONLY the changes introduced in 0.21.5" in inst
    assert "previous version 0.21.2" in inst
    # the whole point: don't relabel older items to the new version
    assert "do not relabel it to 0.21.5" in inst
    assert "(v0.21.2)" in inst
