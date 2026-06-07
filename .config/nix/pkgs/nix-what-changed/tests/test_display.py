from what_changed import display


def test_wrap_indent():
    result = display._wrap("short", indent="  ↳ ", subsequent="    ")
    assert "short" in result
    assert result.startswith("  ↳ ")


def test_show_package_no_bullets(capsys):
    display.show_package("test-pkg", "1.0", "2.0", None, None, 18)
    captured = capsys.readouterr()
    assert "test-pkg" in captured.out
    assert "1.0" in captured.out
    assert "2.0" in captured.out


def test_show_package_with_description(capsys):
    display.show_package("pkg", "1", "2", "Some description", None, 18)
    captured = capsys.readouterr()
    assert "↳" in captured.out or "Some description" in captured.out


def test_show_package_with_bullets(capsys):
    display.show_package("pkg", "1", "2", None, ["First change", "Second change"], 18)
    captured = capsys.readouterr()
    assert "• First change" in captured.out
    assert "• Second change" in captured.out


def test_show_package_truncates_bullets(capsys):
    many = [f"Change {i}" for i in range(10)]
    display.show_package("pkg", "1", "2", None, many, 18)
    captured = capsys.readouterr()
    assert "more changes" in captured.out


def test_show_header(capsys):
    display.show_header(5)
    captured = capsys.readouterr()
    assert "5" in captured.out


def test_show_footer(capsys):
    display.show_footer(3)
    captured = capsys.readouterr()
    assert "3" in captured.out
