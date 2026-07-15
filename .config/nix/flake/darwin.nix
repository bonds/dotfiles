{
  self,
  inputs,
  ...
}: let
  mkDarwin = import ./../lib/mkDarwin.nix {
    inherit self inputs;
    inherit
      (inputs)
      nix-darwin
      nixpkgs
      nixpkgs-unstable
      home-manager
      nix-index-database
      agenix
      ;
  };
  vudialsPkgs = (import ./../lib/vudials-packages.nix) inputs.vudials (
    import inputs.nixpkgs {
      system = "aarch64-darwin";
      config.allowUnfree = true;
    }
  );
in {
  flake.darwinConfigurations = {
    accismus = (import ./../hosts/accismus/default.nix) {inherit mkDarwin vudialsPkgs inputs;};
  };
}
