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
    result = summarize._postprocess(["the the same", "word word repeat"], cfg)
    assert result == ["the same", "word repeat"]


def test_postprocess_word_merge():
    cfg = Config()
    result = summarize._postprocess(["forMathe", "theXcerpt"], cfg)
    assert result == ["for Mathe", "the Xcerpt"]


def test_summarize_short_text_returns_none():
    cfg = Config()
    result = summarize.summarize("test", "short", cfg)
    assert result is None
