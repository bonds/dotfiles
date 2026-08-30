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
          statix check . 2>&1 || (echo "Run: statix fix ." && exit 1)
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

        photo-export-test = mkCheck "photo-export-test" [] ''
          # Unit tests for photokit-export's pure logic. Needs Xcode's swiftc
          # (system SDK), not nixpkgs `swift`. The CLI has top-level code, so
          # copy the test to main.swift for multi-file compile.
          TOOLCHAIN="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain"
          SWIFTC="$TOOLCHAIN/usr/bin/swiftc"
          RESDIR="$TOOLCHAIN/usr/lib/swift"
          SDKROOT="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
          modcache="$TMPDIR/swiftmodule-cache"
          mkdir -p "$modcache"
          tmpdir="$TMPDIR/petest"
          mkdir -p "$tmpdir"
          cp ${self}/pkgs/photokit-export/photoexport_core.swift "$tmpdir/photoexport_core.swift"
          cp ${self}/pkgs/photokit-export/test_core.swift "$tmpdir/main.swift"
          "$SWIFTC" -module-cache-path "$modcache" -sdk "$SDKROOT" -resource-dir "$RESDIR" \
            -o "$tmpdir/test" "$tmpdir/photoexport_core.swift" "$tmpdir/main.swift" \
            || (echo "compile failed" >&2 && exit 1)
          "$tmpdir/test"
        '';
      };
  };
}
