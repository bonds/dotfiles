# install-openfang (ARCHIVED 2026-10-01 — implementation diverged)

Package OpenFang (Rust Agent OS) as a lix binary package and install it on the sophrosyne NixOS server via environment.systemPackages

## Outcome / divergence

The change as written was **not** implemented. What actually shipped is a
**darwin** overlay on accismus, not a NixOS package on sophrosyne:

- Implemented: `modules/overlays/openfang/default.nix` — a `mkDarwinPackage`
  overlay fetching the macOS `OpenFang_aarch64.app.tar.gz`, wired into
  accismus via `home.packages` (`modules/home/macos-apps.nix`).
- Not implemented: `pkgs/openfang/default.nix` (x86_64-linux tarball) and the
  `environment.systemPackages` entry in `hosts/sophrosyne/configuration.nix`.
- The packaged release also moved on (overlay pins `0.6.9`); license is
  Apache-2.0 (the proposal guessed `unfree`).

Archived as-is rather than archived-with-spec-merge: the spec's platform and
delivery model were wrong, so promoting it to `openspec/specs/` would enshrine
something that never existed. If OpenFang is ever wanted on sophrosyne, open a
new change against the real (darwin) implementation.
