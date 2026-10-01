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

        deadnix-check = mkCheck "deadnix-check" [pkgs.deadnix] ''
          # -L: don't check lambda attrset pattern names (breaks nixpkgs
          # callPackage name-resolution, e.g. transcribe-cpp explicit arg).
          # Unused *let bindings* are still checked.
          deadnix -L --fail . 2>&1 || (echo "Run: deadnix -w ." && exit 1)
        '';

        statix-check = mkCheck "statix-check" [pkgs.statix] ''
          # Auto-discovers statix.toml at the repo root (repeated_keys
          # disabled there). Do NOT use --config: statix silently ignores
          # config files inside /nix/store (oppiliappan/statix#71), and this
          # check runs with cwd = ${self} which IS a store path.
          statix check . 2>&1 || (echo "Run: statix check ." && exit 1)
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

        # nix-what-changed carries a real pytest suite, but it lives in a
        # sub-flake whose checks the root flake never invoked — so it never
        # ran. Run the same tests from the root flake, mirroring the sub-flake's
        # `pytest` check: the python env needs pytest plus the package's runtime
        # deps (the tests import what_changed, whose modules import rich/httpx/
        # pyspellchecker), and PYTHONPATH must expose the package source.
        what-changed-test =
          mkCheck "what-changed-test"
          [(pkgs.python3.withPackages (ps: [ps.pytest ps.tomli-w ps.httpx ps.rich ps.pyspellchecker]))]
          ''
            export HOME=$(mktemp -d)
            export PYTHONPATH=${self}/pkgs/nix-what-changed''${PYTHONPATH:+:$PYTHONPATH}
            pytest ${self}/pkgs/nix-what-changed/tests -v --tb=short -p no:cacheprovider
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
