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
    """Build a single nix expression that fetches changelog, description, homepage for all pkgs."""
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
        }};
      }}) [ {attrs} ]);
    in builtins.toJSON result
    '''


def get_metadata_batch(pkgs: list[str], timeout: int = 60) -> dict[str, dict[str, str | None]]:
    """Get changelog, description, homepage for all pkgs in a single nix eval call."""
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
        }
    return results


def get_changelog_url(pkg: str) -> str | None:
    return nix_eval(f"nixpkgs#{pkg}.meta.changelog")


def get_description(pkg: str) -> str | None:
    return nix_eval(f"nixpkgs#{pkg}.meta.description")


def get_homepage(pkg: str) -> str | None:
    return nix_eval(f"nixpkgs#{pkg}.meta.homepage")
