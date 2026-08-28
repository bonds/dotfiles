import json

from what_changed.metadata import get_flake_repo, get_src_url

_GH_ERMES = {
    "lastModified": 1787914865,
    "narHash": "sha256-AAAA",
    "owner": "NousResearch",
    "repo": "hermes-agent",
    "rev": "c30ac90a92097058ddd6f9db3fa2e3182a7bfdcc",
    "type": "github",
}


def _lock(nodes):
    return json.dumps({"nodes": nodes})


def test_flake_repo_github_input(tmp_path):
    lock = _lock({"hermes-agent": {"locked": _GH_ERMES}})
    p = tmp_path / "flake.lock"
    p.write_text(lock)
    assert get_flake_repo("hermes-agent", str(tmp_path)) == ("NousResearch", "hermes-agent")


def test_flake_repo_non_github_input_returns_none(tmp_path):
    lock = _lock({"somegit": {"locked": {"type": "git", "url": "https://x/y"}}})
    (tmp_path / "flake.lock").write_text(lock)
    assert get_flake_repo("somegit", str(tmp_path)) is None


def test_flake_repo_missing_input_returns_none(tmp_path):
    lock = _lock({"hermes-agent": {"locked": _GH_ERMES}})
    (tmp_path / "flake.lock").write_text(lock)
    assert get_flake_repo("nonexistent-input", str(tmp_path)) is None
    assert get_flake_repo("hermes-agent", str(tmp_path / "no_such_dir")) is None


def test_flake_repo_non_github_input_returns_none_even_chain(tmp_path):
    # A node that is a follows (references elsewhere) with no locked -> None
    lock = _lock({"hermes-agent": {"inputs": {"something": ["foo"]}}})
    (tmp_path / "flake.lock").write_text(lock)
    assert get_flake_repo("hermes-agent", str(tmp_path)) is None


def test_flake_repo_invalid_json_returns_none(tmp_path):
    (tmp_path / "flake.lock").write_text("not json")
    assert get_flake_repo("hermes-agent", str(tmp_path)) is None


def test_get_src_url_builds_installable_expression(monkeypatch):
    # `get_src_url` must emit a bare `nixpkgs#<pkg>.src.url` installable (NOT a
    # parenthesized `or null` expr, which isn't a valid installable and thus
    # makes `nix eval` fail -> None). Regression for the `or null` bug.
    captured = {}

    def fake_nix_eval(expr):
        captured["expr"] = expr
        return "https://github.com/htop-dev/htop/archive/refs/tags/3.5.1.tar.gz"

    monkeypatch.setattr("what_changed.metadata.nix_eval", fake_nix_eval)
    assert get_src_url("htop") == "https://github.com/htop-dev/htop/archive/refs/tags/3.5.1.tar.gz"
    assert captured["expr"] == "nixpkgs#htop.src.url"