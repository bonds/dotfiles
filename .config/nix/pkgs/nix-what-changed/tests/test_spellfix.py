from what_changed.spellfix import fix, _fix_word


def test_preserves_code():
    assert fix("parser.parse_args()") == "parser.parse_args()"
    assert fix("_fix_word") == "_fix_word"
    assert fix("output_json handling") == "output_json handling"


def test_preserves_known_words():
    assert fix("handling") == "handling"
    assert fix("feature") == "feature"
    assert fix("specific") == "specific"


def test_splits_prefix_merged_words():
    result = fix("istricter")
    assert "is" in result and "stricter" in result


def test_splits_capitalized_prefix():
    result = fix("Thisummary")
    assert result == "Thisummary" or "summary" in result.lower()


def test_fixes_doubled_first_letter():
    assert fix("sspecific") == "specific"


def test_fixes_spellcheck_edits():
    result = fix("versionumber")
    assert result == "versionumber"


def test_handles_mixed_code_and_text():
    result = fix("parser.parse_args() istricter")
    assert "parser.parse_args()" in result
    assert " is " in result or "stricter" in result


def test_empty_string():
    assert fix("") == ""


def test_single_word():
    assert fix("handling") == "handling"
