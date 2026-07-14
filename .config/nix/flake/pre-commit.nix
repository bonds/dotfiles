{
  self,
  inputs,
  ...
}: {
  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }: let
    pre-commit-hooks-lib = inputs.pre-commit-hooks.lib.${system};
    pre-commit-check = pre-commit-hooks-lib.run {
      src = self;
      excludes = ["flake.lock"];
      hooks = {
        alejandra.enable = true;
        deadnix.enable = true;
      };
    };
  in {
    checks = {
      inherit pre-commit-check;
    };
    devShells = {
      pre-commit = pkgs.mkShell {
        inherit (pre-commit-check) shellHook;
      };
      default = pkgs.mkShell {
        inherit (pre-commit-check) shellHook;
        packages =
          [pkgs.alejandra pkgs.nix-update]
          ++ lib.optionals pkgs.stdenv.isLinux [pkgs.nh];
      };
    };
  };
}
