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
    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
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

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  nixConfig = {
    extra-substituters = [
      "https://cache.garnix.io"
      "https://nix-community.cachix.org"
      "https://zen-browser.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78bD7HEGj2x7a7Bs="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "zen-browser.cachix.org-1:6ABdUuAq2NIDh3tKf/5uAn7LoFO2duBBLgJMhsF3cig="
    ];
  };
  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [./flake/default.nix];
    };
}
