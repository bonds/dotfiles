{self, ...}: {
  perSystem = {pkgs, ...}: let
    mkCheck = name: buildInputs: script:
      pkgs.runCommand name {inherit buildInputs;} ''
        cd ${self}
        ${script}
        touch $out
      '';
  in {
    checks = {
      format-check = mkCheck "format-check" [pkgs.alejandra] ''
        alejandra -c . || (echo "Run: alejandra ." && exit 1)
      '';
      secrets-check = mkCheck "secrets-check" [pkgs.gitleaks] ''
        gitleaks detect \
          --source . \
          --no-git \
          -c ${self}/.gitleaks.toml \
          --verbose \
          --exit-code 1
      '';
    };
  };
}
