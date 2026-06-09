from what_changed import cache
from what_changed.config import Config


def test_summary_round_trip(tmp_path):
    cfg = Config()
    cfg.cache_dir = str(tmp_path)
    cache.set_summary("test-pkg", "1.0", "2.0", ["bullet 1", "bullet 2"], cfg)
    result = cache.get_summary("test-pkg", "1.0", "2.0", cfg)
    assert result == ["bullet 1", "bullet 2"]


def test_summary_cache_miss(tmp_path):
    cfg = Config()
    cfg.cache_dir = str(tmp_path)
    result = cache.get_summary("nonexistent", "1.0", "2.0", cfg)
    assert result is None


def test_summary_none_bullets(tmp_path):
    cfg = Config()
    cfg.cache_dir = str(tmp_path)
    cache.set_summary("test-pkg", "1.0", "2.0", None, cfg)
    result = cache.get_summary("test-pkg", "1.0", "2.0", cfg)
    assert result is None


def test_changelog_round_trip(tmp_path):
    cfg = Config()
    cfg.cache_dir = str(tmp_path)
    cache.set_changelog("https://example.com/changelog", "changelog text here", cfg)
    result = cache.get_changelog("https://example.com/changelog", cfg)
    assert result == "changelog text here"


def test_changelog_cache_miss(tmp_path):
    cfg = Config()
    cfg.cache_dir = str(tmp_path)
    result = cache.get_changelog("https://example.com/nonexistent", cfg)
    assert result is None


def test_metadata_round_trip(tmp_path):
    cfg = Config()
    cfg.cache_dir = str(tmp_path)
    meta = {"changelog": "https://example.com/cl", "description": "A test pkg", "homepage": "https://example.com"}
    cache.set_metadata("test-pkg", meta, cfg)
    result = cache.get_metadata("test-pkg", cfg)
    assert result is not None
    assert result["changelog"] == "https://example.com/cl"
    assert result["description"] == "A test pkg"
    assert result["homepage"] == "https://example.com"


def test_metadata_cache_miss(tmp_path):
    cfg = Config()
    cfg.cache_dir = str(tmp_path)
    result = cache.get_metadata("nonexistent", cfg)
    assert result is None


def test_diff_pkg_versions_dont_collide(tmp_path):
    cfg = Config()
    cfg.cache_dir = str(tmp_path)
    cache.set_summary("pkg", "1.0", "2.0", ["old bullets"], cfg)
    cache.set_summary("pkg", "2.0", "3.0", ["new bullets"], cfg)
    assert cache.get_summary("pkg", "1.0", "2.0", cfg) == ["old bullets"]
    assert cache.get_summary("pkg", "2.0", "3.0", cfg) == ["new bullets"]
