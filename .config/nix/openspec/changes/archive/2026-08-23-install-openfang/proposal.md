## Why

OpenFang is an open-source Agent Operating System (single ~32MB Rust binary) that runs autonomous agents (Hands) on schedules, with a local dashboard. Installing it is currently manual (`curl .../install | sh`), which drops an unmanaged binary in `~/.openfang` with no nix tracking, no version pinning, and no rollback path. We want it nix-managed on the sophrosyne NixOS server so the binary is declarative, version-pinned, hashed, and rebuilt atomically with the rest of the system.

## What Changes

- Add a new lix binary package `pkgs/openfang/default.nix` that fetches the official `openfang-x86_64-unknown-linux-gnu.tar.gz` release (pinned `v0.6.9`, sha256-verified), extracts the single `openfang` binary, and installs it to the package bin. Includes a `callPackage`-friendly module comment.
- Wire the package into sophrosyne (`hosts/sophrosyne/configuration.nix`) via `environment.systemPackages` using `pkgs.callPackage`, so a rebuild installs it system-wide.
- No systemd service/daemon is added in this change — install is scoped to putting the managed binary on the server (the user asked to *install* OpenFang; running Hands/daemon is follow-up work).

## Capabilities

### New Capabilities
- `nix/openfang-package`: Nix-managed provisioning of the pinned, hashed OpenFang binary as a buildable package, plus the ability to opt a NixOS host (sophrosyne) into installing it via `environment.systemPackages`.

### Modified Capabilities
<!-- None. This is a new package + host wiring; no existing spec changes. -->

## Impact

- **Repo**: new `pkgs/openfang/default.nix` under `~/.config/nix/pkgs/`; edit `hosts/sophrosyne/configuration.nix`.
- **Dependencies**: lix package-builder APIs already used by `pkgs/bedrock-server` (`stdenv.mkDerivation`, `fetchurl`, native build inputs, `callPackage`). OpenFang release asset via GitHub.
- **Systems**: sophrosyne (NixOS); accismus/metanoia unaffected.
- **No external service ports** opened; no secrets touched.