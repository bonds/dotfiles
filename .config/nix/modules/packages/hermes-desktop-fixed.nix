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
  # Built from ${electron.version} in hermes-agent's nix/desktop.nix; 43.6.0 is
  # what nixpkgs-unstable (02f5696b) resolves `electron` to today.
  headersUrl = "https://artifacts.electronjs.org/headers/dist/v43.6.0/node-v43.6.0-headers.tar.gz";

  servedSha256 = "sha256-xDgc5PpkcLpWHnlqVcjBD3SxJKtkUoSGLnJaSSrxJtI=";

  # The nixpkgs hermes-agent follows (inputs.nixpkgs.follows = "nixpkgs-unstable"
  # in flake.nix), not the caller's stable one.
  unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  pkgsWithServedHeaders =
    unstablePkgs
    // {
      fetchurl = args:
        if (args.url or "") == headersUrl
        then unstablePkgs.fetchurl (builtins.removeAttrs args ["hash" "sha256"] // {sha256 = servedSha256;})
        else unstablePkgs.fetchurl args;
    };
in
  inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.desktop.override {
    pkgs = pkgsWithServedHeaders;
  }
