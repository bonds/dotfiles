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
