{
  pkgs,
  lib,
  cfg,
}: let
  numSources = toString (builtins.length (builtins.attrNames cfg.sources));
  pythonBin =
    pkgs.writers.writePython3Bin "firesafe-status-inner" {
      libraries = [pkgs.python3Packages.rich];
      flakeIgnore = ["E501" "F401"];
    }
    (builtins.readFile ./status.py);
in
  pkgs.writeShellScriptBin "firesafe-status" ''
    exec ${pythonBin}/bin/firesafe-status-inner ${cfg.mountPoint} ${numSources} "$@"
  ''
