from __future__ import annotations

import json
import platform
import subprocess

SYSTEM = f"{platform.machine()}-darwin" if platform.system() == "Darwin" else "x86_64-linux"


def nix_eval(expr: str) -> str | None:
    try:
        result = subprocess.run(
            ["nix", "eval", "--raw", expr],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode == 0:
            val = result.stdout.strip()
            return None if val == "null" or not val else val
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass
    return None


def _metadata_expr(pkgs: list[str]) -> str:
    """Build a single nix expression that fetches changelog, description, homepage, src for all pkgs."""
    attrs = " ".join(f'"{p}"' for p in pkgs)
    return f'''
    let
      flake = builtins.getFlake "nixpkgs";
      pkgs = flake.legacyPackages.{SYSTEM};
      result = builtins.listToAttrs (map (name: {{
        name = name;
        value = {{
          changelog = pkgs.${{name}}.meta.changelog or null;
          description = pkgs.${{name}}.meta.description or null;
          homepage = pkgs.${{name}}.meta.homepage or null;
          srcUrl = pkgs.${{name}}.src.url or null;
        }};
      }}) [ {attrs} ]);
    in builtins.toJSON result
    '''


def get_metadata_batch(pkgs: list[str], timeout: int = 60) -> dict[str, dict[str, str | None]]:
    """Get changelog, description, homepage, srcUrl for all pkgs in a single nix eval call."""
    try:
        result = subprocess.run(
            ["nix", "eval", "--impure", "--expr", _metadata_expr(pkgs)],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        if result.returncode == 0:
            data = json.loads(result.stdout.strip())
            cleaned: dict[str, dict[str, str | None]] = {}
            for pkg, vals in data.items():
                cleaned[pkg] = {
                    k: (None if v == "null" or not v else str(v))
                    for k, v in vals.items()
                }
                # nix JSON uses camelCase srcUrl; normalize to snake_case
                cleaned[pkg]["src_url"] = cleaned[pkg].get("srcUrl")
                cleaned[pkg].pop("srcUrl", None)
            return cleaned
    except Exception:
        pass
    # Fallback: sequential individual calls
    results = {}
    for pkg in pkgs:
        results[pkg] = {
            "changelog": get_changelog_url(pkg),
            "description": get_description(pkg),
            "homepage": get_homepage(pkg),
            "src_url": get_src_url(pkg),
        }
    return results


def get_changelog_url(pkg: str) -> str | None:
    return nix_eval(f"nixpkgs#{pkg}.meta.changelog")


def get_description(pkg: str) -> str | None:
    return nix_eval(f"nixpkgs#{pkg}.meta.description")


def get_homepage(pkg: str) -> str | None:
    return nix_eval(f"nixpkgs#{pkg}.meta.homepage")


def get_src_url(pkg: str) -> str | None:
    """The URL of the source tarball the package builds from (e.g. a GitHub
    archive of the release tag). Encodes owner/repo when the source is GitHub.

    Uses the `nixpkgs#<pkg>.src.url` installable form (like the other metadata
    getters); a package without a src.size/url (or an eval error) yields None.
    """
    return nix_eval(f"nixpkgs#{pkg}.src.url")


def get_flake_repo(pkg: str, flake_path: str | None = None) -> tuple[str, str] | None:
    """Resolve (owner, repo) for a package that is a *flake input* (so it is not
    present in nixpkgs) by reading the config flake's flake.lock.

    A diff-closures package name like 'hermes-agent' maps to the flake input
    attribute of the same name; its locked node carries owner/repo/type. Returns
    None for non-github inputs (git, path, etc.) or if untouched by this flake.
    """
    import os

    base = flake_path and os.path.expanduser(flake_path)
    if not base:
        return None
    lock_path = os.path.join(base, "flake.lock")
    try:
        with open(lock_path) as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return None
    node = (data.get("nodes") or {}).get(pkg) or {}
    locked = node.get("locked") or {}
    if locked.get("type") != "github":
        return None
    owner, repo = locked.get("owner"), locked.get("repo")
    if owner and repo:
        return owner, repo
    return None
