let
  zenPolicies = import ../../home/zen-policies.nix;
  zenIcon = ../../zen-icon.icns;
in
  final: prev: {
    zen-browser = final.mkDarwinPackage {
      pname = "zen-browser";
      version = "1.21.8b";

      src = prev.fetchurl {
        url = "https://github.com/zen-browser/desktop/releases/download/1.21.8b/zen.macos-universal.dmg";
        hash = "sha256-TVTFJ7Hhh2Kn12sOzwzpWaKTKf4KaPc32X5kThM0Hgc=";
      };

      nativeBuildInputs = [prev.undmg];

      installPhase = ''
        mkdir -p $out/Applications/Zen.app/Contents/Resources/distribution

        cp -r Zen.app $out/Applications/
        rm -f $out/Applications/Zen.app/.DS_Store

        cp ${zenIcon} $out/Applications/Zen.app/Contents/Resources/firefox.icns

        # policies.json is how Firefox-derived browsers on macOS read enterprise
        # policies natively. This is equivalent to nixpkgs' .override { extraPolicies }
        # used on Linux — both consume the same zen-policies.nix. Do NOT switch to
        # .override here; it doesn't apply to fetchurl-based overlays.
        cat > $out/Applications/Zen.app/Contents/Resources/distribution/policies.json <<POLICIES_EOF
        ${builtins.toJSON {policies = zenPolicies;}}
        POLICIES_EOF

        mkdir -p $out/bin
        ln -s $out/Applications/Zen.app/Contents/MacOS/zen $out/bin/zen
      '';

      meta = {
        description = "Welcome to a calmer internet";
        homepage = "https://zen-browser.app";
        license = prev.lib.licenses.mpl20;
        platforms = ["aarch64-darwin" "x86_64-darwin"];
      };
    };
  }
