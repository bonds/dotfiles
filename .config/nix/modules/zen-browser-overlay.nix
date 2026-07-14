let
  zenPolicies = import ./home/zen-policies.nix;
  zenIcon = ./zen-icon.icns;
in
  final: prev: let
    mkDarwinPackage = import ../lib/mkDarwinPackage.nix {inherit (prev) stdenvNoCC lib;};
  in {
    zen-browser = mkDarwinPackage {
      pname = "zen-browser";
      version = "1.21.6b";

      src = prev.fetchurl {
        url = "https://github.com/zen-browser/desktop/releases/download/1.21.6b/zen.macos-universal.dmg";
        hash = "sha256-oVUjVm3RSQvEan/2DswdBWD3ZNaGm05f8szuMr+VYso=";
      };

      nativeBuildInputs = [prev.undmg];

      installPhase = ''
        mkdir -p $out/Applications/Zen.app/Contents/Resources/distribution

        cp -r Zen.app $out/Applications/
        rm -f $out/Applications/Zen.app/.DS_Store

        cp ${zenIcon} $out/Applications/Zen.app/Contents/Resources/firefox.icns

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
