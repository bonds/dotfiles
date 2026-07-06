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
      home-manager
      nix-index-database
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
