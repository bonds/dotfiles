{
  pkgs,
  lib,
  cfg,
}: let
  script = builtins.readFile ./status.py;
  script' =
    builtins.replaceStrings
    ["@mountPoint@" "@totalSources@"]
    [cfg.mountPoint (toString (builtins.length (builtins.attrNames cfg.sources)))]
    script;
in
  pkgs.writers.writePython3Bin "firesafe-status" {
    libraries = [pkgs.python3Packages.rich];
    flakeIgnore = ["E501"];
  }
  script'
