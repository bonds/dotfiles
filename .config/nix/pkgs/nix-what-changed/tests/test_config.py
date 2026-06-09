import os
import tomllib

from what_changed.config import Config, load


def test_defaults():
    cfg = Config()
    assert cfg.backend == "ollama"
    assert cfg.model == "qwen2.5:1.5b"
    assert cfg.timeout == 40
    assert cfg.max_bullets == 5


def test_load_from_file(tmp_path):
    cfg_path = tmp_path / "config.toml"
    cfg_path.write_text('model = "test-model"\ntimeout = 99\n')
    cfg = load(str(cfg_path))
    assert cfg.model == "test-model"
    assert cfg.timeout == 99
    assert cfg.backend == "ollama"


def test_unknown_keys_ignored(tmp_path):
    cfg_path = tmp_path / "config.toml"
    cfg_path.write_text('unknown_key = "whatever"\nbackend = "openai"\n')
    cfg = load(str(cfg_path))
    assert cfg.backend == "openai"


def test_missing_file_uses_defaults(tmp_path):
    cfg = load(str(tmp_path / "nonexistent.toml"))
    assert cfg.backend == "ollama"


def test_config_fields_match_fetch():
    from what_changed.config import Config
    from what_changed.fetch import fetch_changelog
    import what_changed.urls as urls
    cfg = Config()
    assert hasattr(cfg, "http_timeout")
    assert hasattr(cfg, "gh_timeout")
    assert hasattr(cfg, "max_changelog_bytes")
    assert hasattr(cfg, "timeout")
    assert hasattr(cfg, "model")
