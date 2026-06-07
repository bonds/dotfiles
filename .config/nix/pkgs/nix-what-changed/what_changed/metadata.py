import subprocess


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


def get_changelog_url(pkg: str) -> str | None:
    return nix_eval(f"nixpkgs#{pkg}.meta.changelog")


def get_description(pkg: str) -> str | None:
    return nix_eval(f"nixpkgs#{pkg}.meta.description")


def get_homepage(pkg: str) -> str | None:
    return nix_eval(f"nixpkgs#{pkg}.meta.homepage")
