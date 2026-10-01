## Context

This flake packages native binaries with the **lix** package builder. `pkgs/bedrock-server/default.nix` is the canonical precedent: it uses `stdenv.mkDerivation rec { ... }` with `src = fetchurl { url, hash }`, `nativeBuildInputs`, and an `installPhase`, and is wired into hosts via `pkgs.callPackage`. sophrosyne is x86_64-linux. OpenFang distributes a single-binary tarball from GitHub releases (`openfang-x86_64-unknown-linux-gnu.tar.gz`), which is a near-perfect match for this packaging model.

See proposal.md for the "why".

## Goals / Non-Goals

**Goals:**
- Provide a buildable, version-pinned (v0.6.9), sha256-verified `openfang` lix package.
- Wire it into sophrosyne via `environment.systemPackages`.
- Keep the implementation consistent with the existing `bedrock-server` pattern so maintainers recognize it.

**Non-Goals:**
- No systemd daemon/service or Hands activation — the request is to *install* the managed binary only.
- No packaging for accismus (aarch64-darwin) or metanoia in this change.
- No automatic major-version churn from `latest`.

## Decisions

- **Pin v0.6.9 explicitly** (URL `.../releases/download/v0.6.9/openfang-x86_64-unknown-linux-gnu.tar.gz`) rather than `releases/latest`. This gives a stable hash and reproducible builds; OpenFang is pre-1.0 and ships breaking changes between minors, so an uncontrolled `latest` is risky. Alternative considered: `latest` download with recomputed hash — rejected (breaks on the next release, and the published `.sha256` wants a specific tag anyway).
- **Use `fetchurl` for the tarball and the lix native extraction helper for `.tar.gz`**, mirroring how bedrock uses `unzip`. The tarball contains exactly one file named `openfang`, so install is a single copy into `$out/bin`.
- **Include `autoPatchelfHook`** in `nativeBuildInputs` (like bedrock) so the prebuilt Rust binary gets re-patched for this system's glibc/lib paths if needed — protects against the common binary-drop-portability failure.
- **Wire via `pkgs.callPackage` in `environment.systemPackages`** — the established pattern already used for `rsync-tmbackup` (and it reads exactly like bedrock's sibling usage would).
- **Source provenance/license marked `binaryNativeCode` / `unfree`** to reflect a distributed prebuilt binary.

## Risks / Trade-offs

- [OpenFang is pre-1.0 with breaking changes between minors] → pin the exact tag; bump deliberately when adopting newer versions.
- [GitHub `releases/latest` asset URL noise] → avoided entirely by pinning `download/v0.6.9/...`.
- [Prebuilt binary may not link against this system's glibc] → `autoPatchelfHook` in nativeBuildInputs mitigates; a failed build surfaces the issue loudly rather than shipping a broken binary.
- [Hash must be re-pinned on every version bump] → accepted; this is the cost of reproducibility and is a one-line edit in `default.nix`.

## Migration Plan

Creation of a new package + host wiring only. Deploy by rebuilding sophrosyne from the pushed flake (`nr` / remote rebuild); rollback is a revert of the two touched files followed by a rebuild.

## Open Questions

None — the scope (install only, no service) is well defined; daemon/service config is a separate follow-up.