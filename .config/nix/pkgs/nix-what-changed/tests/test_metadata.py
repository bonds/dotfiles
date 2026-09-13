import json

from what_changed.metadata import _metadata_expr, _system_name, get_flake_repo, get_src_url

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

def test_metadata_expr_falls_back_to_python3packages():
    # Python-only packages (e.g. slack-sdk, tornado) are not top-level pkgs
    # attrs; the batch expression must fall back to python3Packages.<name> or
    # their src/homepage/changelog would all come back null and what-changed
    # would find no changelog.
    expr = _metadata_expr(["slack-sdk", "tornado"])
    assert "pkgs.python3Packages" in expr
    assert '"slack-sdk"' in expr
    assert '"tornado"' in expr


def test_system_name_maps_apple_silicon_to_aarch64_darwin():
    # nixpkgs keys darwin legacyPackages on 'aarch64-darwin' (Nix's canonical
    # name); Python's platform.machine() reports Apple Silicon as 'arm64'. An
    # unmapped 'arm64-darwin' makes the batch metadata eval fail on macOS ARM.
    assert _system_name("arm64", "Darwin") == "aarch64-darwin"
    assert _system_name("aarch64", "Darwin") == "aarch64-darwin"
    assert _system_name("x86_64", "Darwin") == "x86_64-darwin"
    assert _system_name("x86_64", "Linux") == "x86_64-linux"
