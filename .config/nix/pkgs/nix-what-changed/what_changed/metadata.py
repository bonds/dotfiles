from __future__ import annotations

import json
import platform
import subprocess


def _system_name(machine: str, system: str) -> str:
    """Nix system string from Python's platform values.

    nixpkgs keyed its darwin legacyPackages on 'aarch64-darwin' (Nix's canonical
    name), while Python's platform.machine() reports Apple Silicon as 'arm64' —
    an unmapped 'arm64-darwin' makes the whole batch metadata eval fail.
    """
    if system == "Darwin":
        return f"{'aarch64' if machine in ('arm64', 'aarch64') else machine}-darwin"
    return "x86_64-linux"


SYSTEM = _system_name(platform.machine(), platform.system())


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
      py = pkgs.python3Packages;
      # Some packages (mostly Python libraries: slack-sdk, tornado, ...) exist
      # only as python3Packages.<name>, not as a top-level pkgs.<name> attr.
      # Fall back so their src/homepage/changelog still resolve; {{}} keeps the
      # `or null` below happy for genuinely unknown names.
      # `nix store diff-closures` prints some python packages with an
      # interpreter prefix (e.g. python3.12-ctranslate2) that matches no
      # attribute in pkgs or python3Packages. Strip the prefix and retry in
      # the python set so src/homepage/changelog resolve to the parent attr.
      stripPyPrefix = name:
        let m = builtins.match "python3(\\\\.[0-9]+)?-(.*)" name;
        in if m == null then name else builtins.elemAt m 1;
      pkg = name:
        if pkgs ? ${{name}} then pkgs.${{name}}
        else if py ? ${{name}} then py.${{name}}
        else if py ? ${{stripPyPrefix name}} then py.${{stripPyPrefix name}}
        else {{}};
      result = builtins.listToAttrs (map (name: {{
        name = name;
        value = {{
          changelog = (pkg name).meta.changelog or null;
          description = (pkg name).meta.description or null;
          homepage = (pkg name).meta.homepage or null;
          srcUrl = (pkg name).src.url or null;
        }};
      }}) [ {attrs} ]);
    in builtins.toJSON result
    '''


def get_metadata_batch(pkgs: list[str], timeout: int = 60) -> dict[str, dict[str, str | None]]:
    """Get changelog, description, homepage, srcUrl for all pkgs in a single nix eval call."""
    try:
        result = subprocess.run(
            # --raw prints the toJSON string's contents verbatim; without it nix
            # emits a quoted/escaped string and json.loads below gets a str, so
            # the batch silently fell back to slow per-package evals (which also
            # can't resolve python3Packages-only packages).
            ["nix", "eval", "--impure", "--raw", "--expr", _metadata_expr(pkgs)],
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
