{self, ...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: {
    packages = lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      # NON-HERMETIC manual test for photokit-export's pure logic.
      #
      # It compiles against the HOST Xcode toolchain and SDK (swiftc at an
      # absolute /Applications/Xcode.app path) — the same deliberate
      # trade-off pkgs/photokit-export documents for the package itself, so
      # the test re-encodes that host dependency. That is why it lives here
      # as a package, NOT in `checks`: `nix flake check` builds every check,
      # and a check that assumes host state would fail on any machine without
      # that exact Xcode and make `nix flake check` useless there.
      #
      # Run it explicitly on a machine that has Xcode:
      #   nix build .#photo-export-test
      photo-export-test =
        pkgs.runCommand "photo-export-test" {
          preferLocalBuild = true;
          meta.description = "Manual (non-hermetic) unit test for photokit-export core logic; requires host Xcode";
        } ''
          # The CLI has top-level code, so copy the test to main.swift for a
          # multi-file compile.
          TOOLCHAIN="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain"
          SWIFTC="$TOOLCHAIN/usr/bin/swiftc"
          RESDIR="$TOOLCHAIN/usr/lib/swift"
          SDKROOT="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
          if [ ! -x "$SWIFTC" ]; then
            echo "photo-export-test requires Xcode at $TOOLCHAIN (not hermetic)" >&2
            exit 1
          fi
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
          touch $out
        '';
    };
  };
}
