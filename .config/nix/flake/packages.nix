{
  self,
  inputs,
  ...
}: let
  darwinOverlays = import ./../lib/darwin-overlays.nix;
in {
  flake.packages.aarch64-darwin = let
    pkgs = import inputs.nixpkgs {
      system = "aarch64-darwin";
      config.allowUnfree = true;
      overlays = darwinOverlays;
    };
  in {
    inherit (pkgs) ollama zen-browser opencode opencode-desktop;
    neocode = inputs.neocode.packages.aarch64-darwin.default;
  };
}
