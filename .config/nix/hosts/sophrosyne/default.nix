{mkNixos}:
mkNixos "sophrosyne" {
  modules = [
    ./configuration.nix
    ../../modules/bash-to-fish.nix
    {modules.bash-to-fish.enable = true;}
    ../../modules/minecraft-bedrock.nix
    ../../modules/dst-server.nix
    ../../modules/firesafe-backup.nix
  ];
}
