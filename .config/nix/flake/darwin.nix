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
in {
  flake.darwinConfigurations = {
    accismus = (import ./../hosts/accismus/default.nix) {inherit mkDarwin inputs;};
  };
}
