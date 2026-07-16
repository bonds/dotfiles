{pkgs}:
pkgs.writeShellScriptBin "prune-generations" (
  if pkgs.stdenv.isDarwin
  then builtins.readFile ./prune-generations.sh
  else ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    exec ${pkgs.nh}/bin/nh clean profile \
      /nix/var/nix/profiles/system \
      --keep 5 \
      --keep-since 30d
  ''
)
