import re
import subprocess
from dataclasses import dataclass


@dataclass
class PackageChange:
    name: str
    old_version: str
    new_version: str


def run_diff(old_system: str, new_system: str) -> list[PackageChange]:
    result = subprocess.run(
        ["nix", "store", "diff-closures", old_system, new_system],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if result.returncode != 0:
        err = result.stderr.strip()
        if "does not exist" in err or "No such file" in err:
            print("  Previous system closure was garbage collected — nothing to compare.", file=__import__("sys").stderr)
        elif "not found" in err.lower():
            print("  One of the specified store paths was not found.", file=__import__("sys").stderr)
        else:
            print(f"Error: {err}", file=__import__("sys").stderr)
        return []

    changes: list[PackageChange] = []
    for line in result.stdout.splitlines():
        m = re.match(r"^([a-zA-Z0-9._-]+): (.+) → (.+)", line)
        if not m:
            continue
        pkg = m.group(1)
        old_ver = re.sub(r",.*$", "", m.group(2)).strip()
        new_ver = re.sub(r",.*$", "", m.group(3)).strip()
        if old_ver != "∅" and new_ver != "∅":
            changes.append(PackageChange(pkg, old_ver, new_ver))
    return changes
