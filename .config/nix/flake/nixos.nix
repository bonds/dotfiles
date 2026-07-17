{
  self,
  inputs,
  ...
}: let
  mkNixos = import ./../lib/mkNixos.nix {
    inherit self inputs;
    inherit
      (inputs)
      nixpkgs
      nixpkgs-unstable
      home-manager
      nix-index-database
      agenix
      ;
  };
in {
  flake.nixosConfigurations = {
    sophrosyne = (import ./../hosts/sophrosyne/default.nix) {inherit mkNixos inputs;};
    metanoia = (import ./../hosts/metanoia/default.nix) {inherit mkNixos inputs;};
  };
}
