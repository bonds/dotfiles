import json

from what_changed.fetch import _extract_text, _HTMLTextExtractor, _resolve_release_body


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
    html = "<html><body><header><nav><p>skip</p></nav></header><p>keep</p></body></html>"
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


# --- hermes-agent: resolve a release body when the git tag != package version ---

BODY = "Hermes Agent v0.20.6 (v2026.8.27)\n\nPatch release. The summary."


def _releases():
    return [
        {"tag_name": "v2026.8.27", "name": "Hermes Agent v0.20.6 (v2026.8.27)", "body": BODY},
        {"tag_name": "v2026.8.19", "name": "Hermes Agent v0.20.5 (v2026.8.19)", "body": "older"},
    ]


def test_resolve_release_body_matches_version():
    assert _resolve_release_body(json.dumps(_releases()), "0.20.6") == BODY


def test_resolve_release_body_returns_none_when_no_match():
    assert _resolve_release_body(json.dumps(_releases()), "0.99.0") is None


def test_resolve_release_body_does_not_partial_match_longer_versions():
    # A 0.20.6 ask must not match a hypothetical release titled v0.20.60.
    text = json.dumps([{"tag_name": "x", "name": "App v0.20.60 (x)", "body": "wrong"}])
    assert _resolve_release_body(text, "0.20.6") is None


def test_resolve_release_body_does_not_fall_through_to_wrong_version():
    # An empty body on the matched release must NOT fall through to a release
    # naming a DIFFERENT version (0.20.5 is not 0.20.6).
    releases = [
        {"tag_name": "v2026.8.27", "name": "App v0.20.6 (x)", "body": "  "},
        {"tag_name": "v2026.8.19", "name": "App v0.20.5 (x)", "body": "real"},
    ]
    assert _resolve_release_body(json.dumps(releases), "0.20.6") is None


def test_resolve_release_body_handles_bad_input():
    assert _resolve_release_body("not json", "0.20.6") is None
    assert _resolve_release_body("{}", "0.20.6") is None
    assert _resolve_release_body(None, "0.20.6") is None
    assert _resolve_release_body(json.dumps(_releases()), None) is None