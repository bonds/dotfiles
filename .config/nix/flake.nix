{
  description = "Scott Bonds <scott@ggr.com> multi-machine flake (darwin + NixOS)";
  inputs = {
    # Stable nixpkgs (primary system packages — avoids cctools ld64 crash on arm64)
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

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
