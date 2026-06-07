{
  description = "what-changed: show nix system package changelogs using LLM";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs { inherit system; config.allowUnfree = true; };
    in
    {
      packages = forAllSystems (system: {
        default = (pkgsFor system).callPackage ./default.nix { };
      });

      overlays.default = final: prev: {
        what-changed = final.callPackage ./default.nix { };
      };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
    };
}
