let
  zenPolicies = import ../../home/zen-policies.nix;
  zenIcon = ../../zen-icon.icns;
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
in
  final: prev: {
    zen-browser =
      if prev.stdenv.hostPlatform.isDarwin
      then
        # Darwin: prebuilt .dmg, wrapped by mkDarwinPackage. The icon and the
        # enterprise policies are baked into the bundle here so the .app is
        # self-contained when Home Manager copies it to
        # ~/Applications/Home Manager Apps. The icon is ALSO applied to that
        # Home Manager copy via a FinderInfo xattr (home.activation.zenIcon in
        # modules/home/macos-apps.nix), because macOS may prefer the bundle's
        # Assets.car over the baked firefox.icns — the xattr is the stronger
        # display override.
        final.mkDarwinPackage rec {
          pname = "zen-browser";
          inherit (sources) version;

          src = prev.fetchurl {
            inherit (sources.aarch64-darwin) url hash;
          };

          nativeBuildInputs = [prev.undmg];

          installPhase = ''
            mkdir -p $out/Applications/Zen.app/Contents/Resources/distribution

            cp -r Zen.app $out/Applications/
            rm -f $out/Applications/Zen.app/.DS_Store

            cp ${zenIcon} $out/Applications/Zen.app/Contents/Resources/firefox.icns

            # policies.json is how Firefox-derived browsers on macOS read
            # enterprise policies natively. Linux goes through wrapFirefox's
            # extraPolicies instead — both consume the same zen-policies.nix.
            cat > $out/Applications/Zen.app/Contents/Resources/distribution/policies.json <<POLICIES_EOF
            ${builtins.toJSON {policies = zenPolicies;}}
            POLICIES_EOF

            mkdir -p $out/bin
            ln -s $out/Applications/Zen.app/Contents/MacOS/zen $out/bin/zen

            # Re-sign ad-hoc. The icon and policies.json written above rewrite a
            # bundle that undmg extracted with Mozilla's Developer ID signature
            # intact, which breaks the code-signature seal. This re-sign is
            # REQUIRED for the app to launch, verified by repeated controlled
            # tests: a broken seal alone is fatal (Gatekeeper/amfid kills a
            # bundle whose Developer ID signature no longer validates), but an
            # ad-hoc signature is not. `codesign --sign -` drops the
            # hardened-runtime flag (flags go from 0x10000(runtime) to
            # 0x2(adhoc)), and amfid permits the resulting app. Do NOT remove
            # this line, and do NOT re-sign with `--options runtime` — adding the
            # hardened-runtime flag back would make it fail again. `--deep`
            # covers the nested helper apps/frameworks.
            /usr/bin/codesign --force --deep --sign - $out/Applications/Zen.app
          '';

          meta = {
            description = "Welcome to a calmer internet";
            homepage = "https://zen-browser.app";
            license = prev.lib.licenses.mpl20;
            platforms = ["aarch64-darwin" "x86_64-darwin"];
          };
        }
      else
        # Linux: prebuilt tarball wrapped by nixpkgs' wrapFirefox (the same
        # mechanism youwen5/zen-browser-flake used), applying the shared
        # policies via extraPolicies.
        prev.wrapFirefox
        (prev.callPackage ./linux.nix {
          inherit (sources) version;
          inherit (sources.${prev.stdenv.hostPlatform.system}) url hash;
        })
        {
          pname = "zen-browser";
          extraPolicies = zenPolicies;
        };
  }
