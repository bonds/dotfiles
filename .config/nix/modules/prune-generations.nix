{pkgs}: let
  script = pkgs.writeText "prune-generations.py" (builtins.readFile ./prune-generations.py);
in
  pkgs.writeShellScriptBin "prune-generations" ''
    exec ${pkgs.python3}/bin/python3 ${script}
  ''
