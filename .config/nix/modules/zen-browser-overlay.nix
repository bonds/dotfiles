let
  zenPolicies = import ./home/zen-policies.nix;
in
  final: prev: {
    zen-browser = prev.stdenvNoCC.mkDerivation {
      pname = "zen-browser";
      version = "1.21.2b";

      src = prev.fetchurl {
        url = "https://github.com/zen-browser/desktop/releases/download/1.21.2b/zen.macos-universal.dmg";
        hash = "sha256-sZAWRngIkVuS9ONNIsiKsxnozYDd5CfkmwxRTw7I86Y=";
      };

      sourceRoot = ".";

      nativeBuildInputs = [prev.undmg];

      installPhase = ''
        mkdir -p $out/Applications/Zen.app/Contents/Resources/distribution

        cp -r Zen.app $out/Applications/
        rm -f $out/Applications/Zen.app/.DS_Store

        cat > $out/Applications/Zen.app/Contents/Resources/distribution/policies.json << POLICIES_EOF
        ${builtins.toJSON zenPolicies}
        POLICIES_EOF

        mkdir -p $out/bin
        ln -s $out/Applications/Zen.app/Contents/MacOS/zen $out/bin/zen
      '';

      dontFixup = true;

      meta = {
        description = "Welcome to a calmer internet";
        homepage = "https://zen-browser.app";
        license = prev.lib.licenses.mpl20;
        platforms = ["aarch64-darwin" "x86_64-darwin"];
        mainProgram = "zen";
      };
    };
  }
