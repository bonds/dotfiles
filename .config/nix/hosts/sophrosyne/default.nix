{mkNixos}:
mkNixos "sophrosyne" {
  modules = [
    ./configuration.nix
    ./hardware-configuration.nix
  ];
}
