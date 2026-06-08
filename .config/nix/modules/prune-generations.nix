{pkgs}:
pkgs.writeShellScriptBin "prune-generations" (builtins.readFile ./prune-generations.sh)
