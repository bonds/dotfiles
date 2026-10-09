{
  description = "Scott Bonds <scott@ggr.com> multi-machine flake (darwin + NixOS)";
  inputs = {
    # ── TEMPORARY PINS — auto-removed by `nr --update` ───────────────────────
    # Both nixpkgs inputs are pinned to commits so that `nr --update` builds.
    # Each is unpinned automatically by `nr-unpin-check` (see
    # .config/fish/conf.d/15-functions.fish), which `nr --update` calls before
    # `nix flake update`: for every pinned input it asks nix whether the
    # offending package would still have to be built from source at the branch
    # head, and restores the moving branch for that input as soon as a
    # substituter has it again.
    #
    # Normally: nixpkgs = nixos-26.05 (primary system packages — avoids the
    # cctools ld64 crash on arm64), nixpkgs-unstable = nixpkgs-unstable.
    #
    # Why each is pinned — in both cases the branch head needs a package built
    # from source whose own test suite fails here, which aborts `nh darwin
    # build`:
    #   * nixpkgs: the stable bump changed python3.13-tokenizers, so it is no
    #     longer substitutable; building it pulls its test deps (datasets →
    #     pyarrow → arrow-cpp → thrift) and thrift 0.24.0's C++ tests do not
    #     compile against libcxx 21 (a Catch2 static_assert, plus an assembler
    #     error). Pinned to the last rev where thrift substitutes.
    #   * nixpkgs-unstable: it moved CPython to 3.12.15, which backports
    #     gh-156793 / CVE-2026-19553 (SSLContext.wrap_bio() now rejects
    #     server_hostname in server mode). anyio 4.14.2's own pytest suite fails
    #     on it and the derivation is absent from every substituter (anyio
    #     arrives through hermes-agent's dep set; hermes follows this input,
    #     see below). Pinned to the last rev whose python312 is 3.12.14.
    #
    # Manual probe (no build of the system needed — nix prints the derivation
    # only when it would have to be built from source):
    #   nix build --dry-run --no-link 'github:NixOS/nixpkgs/nixos-26.05#thrift'
    #   nix build --dry-run --no-link 'github:NixOS/nixpkgs/nixpkgs-unstable#python312Packages.anyio'
    nixpkgs.url = "github:NixOS/nixpkgs/774debe7a0d1b496e35677ad955a1011c6ff74f3";
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
