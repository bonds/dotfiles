_: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: {
    devShells = {
      default = pkgs.mkShell {
        packages =
          [pkgs.alejandra pkgs.nix-update]
          ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [pkgs.nh];
      };
    };
  };
}
