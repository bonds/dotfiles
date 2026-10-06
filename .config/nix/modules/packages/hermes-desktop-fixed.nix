# hermes-desktop, with the electron-headers fetch replaced by nixpkgs' own
# electron.headers output.
#
# BUG-001 workaround (upstream #61443): upstream nix/desktop.nix fetches the
# Electron node-headers tarball with a hardcoded sha256 that drifts whenever
# Electron regenerates its header tarballs, killing the build (and the whole
# accismus closure, since the desktop feeds home-manager-generation) with a
# fixed-output hash mismatch. nixpkgs already ships that exact tarball as a
# maintained fixed-output derivation — `pkgs.electron.headers` (hash kept
# current in nixpkgs' binary/info.json) — so the shim hands desktop.nix a
# `pkgs` whose `fetchurl` returns it: no URL, no hash, no pinned electron
# version, nothing to bump when nixpkgs-unstable moves electron.
#
# desktop.nix only reaches for `pkgs.fetchurl` in the headers call, so every
# other fetchurl passes through untouched. The base is the unstable nixpkgs
# hermes-agent itself follows, not the caller's stable 26.05 one, so
# desktop.nix sees the nixpkgs it was written against for everything else too.
#
# nixpkgs' headers output is UNPACKED (fetchzip-style), but desktop.nix does
# `tar -xzf ${electronHeaders} -C ... --strip-components=1`, which fails on a
# directory ("Error opening archive"). So repack the unpacked tree under the
# same `node-v<version>/` top-level dir the original tarball had — a local
# derivation with no fetch, so still no URL or hash to maintain.
#
# Remove when upstream PR #69458 merges (desktop.nix then uses
# `electron.headers` directly).
{
  pkgs,
  inputs,
}: let
  # The nixpkgs hermes-agent follows (inputs.nixpkgs.follows = "nixpkgs-unstable"
  # in flake.nix), not the caller's stable one.
  unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  # nixpkgs' own headers FOD — same artifacts.electronjs.org tarball, hash
  # maintained upstream. The url check below matches desktop.nix's url
  # construction exactly (verified for electron 43.6.0); both sides are built
  # from the same unstablePkgs.electron, so they move together on a bump.
  headersUrlOf = electron: "https://artifacts.electronjs.org/headers/dist/v${electron.version}/node-v${electron.version}-headers.tar.gz";
  isHeadersFetch = args: args.url or "" == headersUrlOf unstablePkgs.electron;

  # Repack nixpkgs' unpacked headers as the tarball desktop.nix expects:
  # one top-level node-v<ver>/ dir, which its --strip-components=1 peels to
  # the same include/ tree the original tarball yields. Pure local rebuild
  # of an already-fetched store path — no network, no hash.
  headersTarball = unstablePkgs.runCommand "node-v${unstablePkgs.electron.version}-headers-repacked.tar.gz" {} ''
    mkdir -p "$TMPDIR/stage"
    cp -R ${unstablePkgs.electron.headers} "$TMPDIR/stage/node-v${unstablePkgs.electron.version}"
    tar -czf "$out" -C "$TMPDIR/stage" "node-v${unstablePkgs.electron.version}"
  '';

  pkgsWithHeaders =
    unstablePkgs
    // {
      fetchurl = args:
        if isHeadersFetch args
        then headersTarball
        else unstablePkgs.fetchurl args;
    };

  # If nixpkgs-unstable moves electron, desktop.nix builds its headers URL from
  # the NEW version while the url check above is built from the same
  # unstablePkgs.electron, so they move together — but electron.headers must
  # exist. Fail at eval (legible) rather than at fetch (a confusing hash
  # mismatch pointing at nothing).
  headersMissing = !(unstablePkgs.electron ? headers);
in
  pkgs.lib.throwIf headersMissing ''
    hermes-desktop-fixed.nix: nixpkgs-unstable's electron ${unstablePkgs.electron.version} has no `headers` output;
    the BUG-001 shim needs pkgs.electron.headers (nixpkgs maintains its hash in binary/info.json).
  '' (
    inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.desktop.override {
      pkgs = pkgsWithHeaders;
    }
  )
