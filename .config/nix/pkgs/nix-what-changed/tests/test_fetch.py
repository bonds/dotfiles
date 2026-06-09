from what_changed.fetch import _extract_text, _HTMLTextExtractor


def test_extract_text_plain():
    result = _extract_text("hello world\nline two")
    assert result is not None
    assert "hello world" in result
    assert "line two" in result


def test_extract_text_plain_no_html():
    result = _extract_text("plain text\nwithout html\nmultiple lines")
    assert result is not None
    assert "plain text" in result


def test_extract_text_short_returns_none():
    assert _extract_text("") is None
    assert _extract_text("   ") is None


def test_extract_text_skips_html_tags():
    html = "<html><body><p>Hello</p><p>World</p></body></html>"
    result = _extract_text(html)
    assert result is not None
    assert "Hello" in result
    assert "World" in result


def test_extract_text_skips_scripts():
    html = "<html><body><script>bad stuff</script><p>good stuff</p></body></html>"
    result = _extract_text(html)
    assert result is not None
    assert "good stuff" in result
    assert "bad stuff" not in result


def test_extract_text_handles_mw_parser_output():
    html = '<html><body><div class="mw-parser-output"><p>wiki content</p></div></body></html>'
    result = _extract_text(html)
    assert result is not None
    assert "wiki content" in result


def test_extract_text_nested_skip():
    html = '<html><body><header><nav><p>skip</p></nav></header><p>keep</p></body></html>'
    result = _extract_text(html)
    assert result is not None
    assert "keep" in result
    assert "skip" not in result


def test_html_extractor_skip_counter():
    parser = _HTMLTextExtractor()
    parser.handle_starttag("header", [])
    parser.handle_starttag("nav", [])
    assert parser.skip == 2
    parser.handle_endtag("nav")
    assert parser.skip == 1
    parser.handle_endtag("header")
    assert parser.skip == 0


def test_html_extractor_newlines():
    parser = _HTMLTextExtractor()
    parser.handle_starttag("p", [])
    parser.handle_data("text")
    parser.handle_endtag("p")
    result = "".join(parser.text)
    assert "text" in result
