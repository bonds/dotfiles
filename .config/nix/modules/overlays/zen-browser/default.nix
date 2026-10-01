let
  zenPolicies = import ../../home/zen-policies.nix;
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
in
  final: prev: {
    zen-browser =
      if prev.stdenv.hostPlatform.isDarwin
      then
        # Darwin: prebuilt .dmg, wrapped by mkDarwinPackage. The bundle is a
        # pristine `undmg` extraction — NOTHING is rewritten into it, so
        # Mozilla's original Developer ID signature + hardened runtime stay
        # intact and no ad-hoc re-sign is needed. Enterprise policies come from
        # macOS managed preferences (targets.darwin.defaults."app.zen-browser.zen"
        # in modules/home/macos-apps.nix, reuse the shared zen-policies.nix),
        # and the custom icon is applied only to the Home Manager copy via a
        # FinderInfo xattr (home.activation.zenIcon) — neither touches the
        # bundle, so the signature seal is preserved. See AGENTS.md §B.1.
        final.mkDarwinPackage rec {
          pname = "zen-browser";
          inherit (sources) version;

          src = prev.fetchurl {
            inherit (sources.aarch64-darwin) url hash;
          };

          nativeBuildInputs = [prev.undmg];

          installPhase = ''
            mkdir -p $out/Applications
            cp -r Zen.app $out/Applications/
            rm -f $out/Applications/Zen.app/.DS_Store

            mkdir -p $out/bin
            ln -s $out/Applications/Zen.app/Contents/MacOS/zen $out/bin/zen
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
