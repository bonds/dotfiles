# hermes-desktop, with the electron-headers fetch repaired.
#
# BUG-001 workaround (upstream #61443): Electron regenerated its header
# tarballs, so the hash pinned in hermes-agent's nix/desktop.nix no longer
# matches what its URL serves, and the desktop build dies with a fixed-output
# hash mismatch:
#   pinned: sha256-f8bSbLRmtbP93CJAvEBs+sHWDZ1xP2bcpLhC1EnOmZU=
#   served: sha256-xDgc5PpkcLpWHnlqVcjBD3SxJKtkUoSGLnJaSSrxJtI=
# That mismatch aborts the whole accismus closure: the desktop (and so
# hermes-desktop-app) is a dependency of home-manager-generation.
#
# desktop.nix hardcodes the fetchurl, and it takes nothing from `pkgs` except
# that call, so the only handle is the `pkgs` argument of the derivation.
# This redirects that one URL to the hash actually served; every other
# fetchurl call goes through untouched. The base is the unstable nixpkgs
# hermes-agent itself follows, not the caller's stable 26.05 one, so desktop.nix
# sees the nixpkgs it was written against for everything else too.
#
# Remove when upstream PR #69458 merges (desktop.nix then uses
# `electron.headers`, whose hash nixpkgs maintains in binary/info.json).
#
# When nixpkgs-unstable bumps electron, refresh the URL and the hash:
#   nix store prefetch-file --hash-type sha256 https://artifacts.electronjs.org/headers/dist/v<ver>/node-v<ver>-headers.tar.gz
{
  pkgs,
  inputs,
}: let
  # Built from ${electron.version} in hermes-agent's nix/desktop.nix. Pinned
  # here to the version nixpkgs-unstable resolved when this workaround was
  # written — the servedSha256 below is only valid for that exact tarball.
  pinnedElectronVersion = "43.6.0";
  headersUrl = "https://artifacts.electronjs.org/headers/dist/v${pinnedElectronVersion}/node-v${pinnedElectronVersion}-headers.tar.gz";

  servedSha256 = "sha256-xDgc5PpkcLpWHnlqVcjBD3SxJKtkUoSGLnJaSSrxJtI=";

  # The nixpkgs hermes-agent follows (inputs.nixpkgs.follows = "nixpkgs-unstable"
  # in flake.nix), not the caller's stable one.
  unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  # If nixpkgs-unstable moves electron, desktop.nix will build its headers URL
  # from the NEW version, this shim's pinned URL stops matching, and the build
  # fails with the ORIGINAL hash mismatch — with nothing pointing at the stale
  # shim. Warn at eval time so that failure is legible.
  electronMoved = unstablePkgs.electron.version != pinnedElectronVersion;

  pkgsWithServedHeaders =
    unstablePkgs
    // {
      fetchurl = args:
        if (args.url or "") == headersUrl
        then unstablePkgs.fetchurl (builtins.removeAttrs args ["hash" "sha256"] // {sha256 = servedSha256;})
        else unstablePkgs.fetchurl args;
    };
in
  pkgs.lib.warnIf electronMoved ''
    hermes-desktop-fixed.nix: nixpkgs-unstable now has electron ${unstablePkgs.electron.version},
    but this BUG-001 shim is pinned to ${pinnedElectronVersion}. desktop.nix will fetch
    v${unstablePkgs.electron.version} headers, the shim will not match, and the build will
    fail with the ORIGINAL hash mismatch. Refresh pinnedElectronVersion + servedSha256:
      nix store prefetch-file --hash-type sha256 \
        https://artifacts.electronjs.org/headers/dist/v${unstablePkgs.electron.version}/node-v${unstablePkgs.electron.version}-headers.tar.gz
  '' (
    inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.desktop.override {
      pkgs = pkgsWithServedHeaders;
    }
  )
