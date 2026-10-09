{
  description = "Scott Bonds <scott@ggr.com> multi-machine flake (darwin + NixOS)";
  inputs = {
    # Stable nixpkgs (primary system packages — avoids cctools ld64 crash on arm64)
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # ── TEMPORARY PIN — auto-removed by `nr --update` ────────────────────────
    # Unpinned automatically by `nr-unpin-check` (see
    # .config/fish/conf.d/15-functions.fish), which `nr --update` calls before
    # `nix flake update`: it probes nixpkgs-unstable HEAD and restores the
    # moving branch as soon as the blocker below clears.
    #
    # Why it is pinned: nixpkgs-unstable moved CPython to 3.12.15, which
    # backports gh-156793 / CVE-2026-19553 (SSLContext.wrap_bio() now rejects
    # server_hostname in server mode). anyio 4.14.2's own pytest suite fails on
    # it, the derivation is absent from every configured substituter, so it
    # builds from source and fails → `nh darwin build` aborts (anyio arrives
    # through hermes-agent's dep set; hermes follows this input, see below).
    # This rev is the last one whose python312 is 3.12.14, where anyio
    # substitutes cleanly.
    #
    # Manual probe (no build of the system needed):
    #   nix build --no-link 'github:NixOS/nixpkgs/nixpkgs-unstable#python312Packages.anyio'
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/c9fe7d12cd78d1adcd12dd15e24432dde5b155a0";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    vudials = {
      url = "github:bonds/nix-vudials";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    polyptych = {
      url = "github:bonds/polyptych";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    neocode = {
      url = "github:bonds/NeoCode";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hermes Agent (Nous Research) — home-manager module for accismus.
    # FOLLOWS nixpkgs-unstable on purpose (kept on an unstable channel: uv2nix
    # needs packages newer than stable 26.05 ships); unstable→unstable follows
    # is safe — the AGENTS.md gotcha is about following TO a stable channel.
    # Its electron-headers fetch is shimmed in
    # modules/packages/hermes-desktop-fixed.nix (drop with upstream PR #69458).
    hermes-agent.url = "git+https://github.com/NousResearch/hermes-agent?rev=749220ef0007f8d87bd1531f1c24b0fe93816385";
    hermes-agent.inputs.nixpkgs.follows = "nixpkgs-unstable";
    # Dedupe flake.lock's flake-parts_2 node: hermes-agent's flake-parts is only
    # another instance of the same input and follows ours fine. (Its
    # home-manager is NOT made to follow ours: hermes tracks nixpkgs-unstable,
    # our home-manager is release-26.05, and following to a stable channel can
    # break an unstable input — see the AGENTS.md follows gotcha.)
    hermes-agent.inputs.flake-parts.follows = "flake-parts";
  };
  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [./flake/default.nix];
    };
}
