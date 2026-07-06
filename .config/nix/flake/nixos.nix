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
      nixpkgs-stable
      home-manager-stable
      nix-index-database
      ;
  };
  vudialsPkgs = (import ./../lib/vudials-packages.nix) inputs.vudials (
    import inputs.nixpkgs-stable {
      system = "x86_64-linux";
      config.allowUnfree = true;
    }
  );
in {
  flake.nixosConfigurations = {
    sophrosyne = (import ./../hosts/sophrosyne/default.nix) {inherit mkNixos;};
    metanoia = (import ./../hosts/metanoia/default.nix) {inherit mkNixos vudialsPkgs inputs;};
  };
}
