{self, ...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    mkCheck = name: buildInputs: script:
      pkgs.runCommand name {
        inherit buildInputs;
        preferLocalBuild = true;
      } ''
        cd ${self}
        ${script}
        touch $out
      '';
  in {
    checks =
      {
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

        sophrosyne-eval = mkCheck "sophrosyne-eval" [pkgs.nix] ''
          echo "Evaluating sophrosyne NixOS config..." >&2
          nix eval --raw .#nixosConfigurations.sophrosyne.config.system.build.toplevel.drvPath 2>&1 || (echo "FAIL" >&2 && exit 1)
        '';

        metanoia-eval = mkCheck "metanoia-eval" [pkgs.nix] ''
          echo "Evaluating metanoia NixOS config..." >&2
          nix eval --raw .#nixosConfigurations.metanoia.config.system.build.toplevel.drvPath 2>&1 || (echo "FAIL" >&2 && exit 1)
        '';
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        accismus-eval = mkCheck "accismus-eval" [pkgs.nix] ''
          echo "Evaluating accismus darwin config..." >&2
          nix eval --raw .#darwinConfigurations.accismus.config.system.build.toplevel.drvPath 2>&1 || (echo "FAIL" >&2 && exit 1)
        '';
      };
  };
}
