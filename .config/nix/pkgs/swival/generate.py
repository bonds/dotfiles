#!/usr/bin/env python3
"""Regenerate sources.nix for pkgs/swival from upstream's uv.lock.

Swival is a pure-Python CLI with a large, fast-moving dependency closure
(litellm, boto3, google-cloud-aiplatform, tiktoken, ...). None of those
versions exist in nixpkgs, and several ship binary wheels only, so building
the closure from source is not worth it: we vendor the exact wheel set that
`uv tool install swival` would install and unzip it in the derivation.

The wheel set is resolved with pip (against constraints pinned to the
versions in upstream's uv.lock, so the result matches the lock the
maintainers actually test), and every file's hash comes from that same
uv.lock. Both platforms are resolved with explicit --platform tags, so this
script produces identical output whether it runs on accismus or sophrosyne.

Usage:
  generate.py --version 1.9.4 --lock uv.lock --out sources.nix
"""

import argparse
import json
import pathlib
import subprocess
import sys
import tempfile
import tomllib
import urllib.request

# The python minor version the vendored wheels are tagged for. nixpkgs 26.05
# ships 3.13; swival supports >=3.13,<3.15. Keep in sync with default.nix.
PYTHON_VERSION = "3.13"
PYTHON_ABI = "cp313"
EXTRAS = "metaskills"

# pip resolves against these tags, not the build host's, so the output does
# not depend on which machine runs the update:
#   - macOS arm64. nixpkgs builds for 11.0, but some wheels are only published
#     for 12.0/15.0; accismus is on macOS 26, so allow them.
#   - glibc x86_64. manylinux_2_28 is litellm's floor; 2_17/2014 covers the
#     rest. nixpkgs 26.05 is far newer than either.
PLATFORMS = {
    "aarch64-darwin": [
        "macosx_15_0_arm64",
        "macosx_14_0_arm64",
        "macosx_13_0_arm64",
        "macosx_12_0_arm64",
        "macosx_11_0_arm64",
        "macosx_10_15_arm64",
    ],
    "x86_64-linux": [
        "manylinux_2_28_x86_64",
        "manylinux2014_x86_64",
        "manylinux_2_17_x86_64",
    ],
}


def fetch_json(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return json.load(r)


def lock_data(lock_path):
    """filename -> sha256 hex, and package name -> version, from uv.lock."""
    with open(lock_path, "rb") as f:
        lock = tomllib.load(f)
    hashes, versions = {}, {}
    for pkg in lock["package"]:
        versions[pkg["name"]] = pkg["version"]
        files = list(pkg.get("wheels", []))
        if pkg.get("sdist"):
            files.append(pkg["sdist"])
        for f in files:
            name = f["url"].rsplit("/", 1)[-1]
            algo, _, digest = f["hash"].partition(":")  # uv.lock: "sha256:<hex>"
            if algo != "sha256":
                sys.exit(f"generate.py: {name}: unsupported hash {f['hash']}")
            hashes[name] = digest
    return hashes, versions


def resolve(spec, requirement, constraints, tmpdir):
    """filename -> url for the wheels pip would install on one platform."""
    report = pathlib.Path(tmpdir) / f"report-{spec}.json"
    cmd = [
        sys.executable, "-m", "pip", "install",
        "--dry-run", "--quiet", "--no-cache-dir", "--ignore-installed",
        "--only-binary=:all:",
        "--python-version", PYTHON_VERSION,
        "--implementation", "cp",
        "--abi", PYTHON_ABI, "--abi", "abi3",
        "--constraint", str(constraints),
        "--report", str(report),
        "--target", str(pathlib.Path(tmpdir) / f"target-{spec}"),
    ]
    for tag in PLATFORMS[spec]:
        cmd += ["--platform", tag]
    cmd.append(requirement)

    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        sys.exit(f"generate.py: pip resolution failed for {spec}:\n{proc.stdout}{proc.stderr}")
    return {
        i["download_info"]["url"].rsplit("/", 1)[-1]: i["download_info"]["url"]
        for i in json.loads(report.read_text())["install"]
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--lock", required=True, help="uv.lock from the swival release tag")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    requirement = f"swival[{EXTRAS}]=={args.version}"
    hashes, versions = lock_data(args.lock)

    # swival itself is an editable entry in its own lock, so its wheel comes
    # from PyPI.
    pypi = fetch_json(f"https://pypi.org/pypi/swival/{args.version}/json")
    swival_files = {f["filename"]: f for f in pypi["urls"]}
    swival_wheel = next(
        (n for n in swival_files if n.endswith("-py3-none-any.whl")), None
    )
    if swival_wheel is None:
        sys.exit(f"generate.py: no pure-python wheel for swival {args.version}")
    hashes[swival_wheel] = swival_files[swival_wheel]["digests"]["sha256"]

    with tempfile.TemporaryDirectory() as tmpdir:
        # Pin pip to the lock's versions: without this it happily resolves a
        # newer boto3/openai the lock has never seen, and the hash lookup
        # below fails.
        constraints = pathlib.Path(tmpdir) / "constraints.txt"
        constraints.write_text("".join(f"{n}=={v}\n" for n, v in sorted(versions.items())))

        wheels = {spec: resolve(spec, requirement, constraints, tmpdir) for spec in PLATFORMS}

    if swival_wheel not in wheels["aarch64-darwin"]:
        sys.exit(f"generate.py: {swival_wheel} missing from the darwin resolution")

    urls = {}
    for spec_wheels in wheels.values():
        urls.update(spec_wheels)

    all_files = sorted(urls)
    missing = [f for f in all_files if f not in hashes]
    if missing:
        sys.exit("generate.py: no hash in uv.lock for: " + ", ".join(missing))

    out = [
        "# Generated by pkgs/swival/update.sh — do not edit by hand.",
        "#",
        f"# Swival {args.version} wheel set for python {PYTHON_VERSION}, resolved from",
        "# upstream's uv.lock at that release tag. Hashes are that lock's.",
        "{",
        f'  version = "{args.version}";',
        "",
        "  # Every wheel the build can need, keyed by filename.",
        "  files = {",
    ]
    for f in all_files:
        out += [
            f'    "{f}" = {{',
            f'      url = "{urls[f]}";',
            f'      sha256 = "{hashes[f]}";',
            "    };",
        ]
    out += ["  };", "", "  # Which of them each system installs.", "  wheels = {"]
    for spec, files in wheels.items():
        out.append(f"    {spec} = [")
        out += [f'      "{f}"' for f in sorted(files)]
        out.append("    ];")
    out += ["  };", "}"]

    pathlib.Path(args.out).write_text("\n".join(out) + "\n")
    print(
        f"swival: {args.version} — {len(all_files)} wheels "
        f"({len(wheels['aarch64-darwin'])} darwin, {len(wheels['x86_64-linux'])} linux)"
    )


if __name__ == "__main__":
    main()
