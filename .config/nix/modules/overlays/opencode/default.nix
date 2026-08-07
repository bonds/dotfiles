# https://jezenthomas.com/2026/07/nix-overrides-that-expire-themselves/
#
# Self-expiring override: when nixpkgs catches up to our target version,
# the warning fires and tells us to delete this overlay.
#
# We import nixpkgs fresh (via the flake input) to check the version,
# because referencing prev.opencode inside the overlay that defines
# opencode creates an infinite recursion through nixpkgs' by-name overlay.
nixpkgs: final: prev: let
  targetVersion = "1.18.14";
  basePkgs = import nixpkgs {
    system = "aarch64-darwin";
    config.allowUnfree = true;
  };
  useNixpkgs = prev.lib.versionAtLeast basePkgs.opencode.version targetVersion;
in
  prev.lib.warnIf useNixpkgs
  "opencode >= ${targetVersion} is now in nixpkgs, the overlay can be removed."
  {
    opencode =
      if useNixpkgs
      then prev.opencode
      else
        final.mkDarwinPackage rec {
          pname = "opencode";
          version = targetVersion;

          src = prev.fetchurl {
            url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-darwin-arm64.zip";
            hash = "sha256-rYElu2SQhuuSEKh7vSesRTpSbiQyrr1NPJhT4tQuMpE=";
          };

          nativeBuildInputs = [prev.unzip];

          installPhase = ''
            mkdir -p $out/bin
            install -m 755 opencode $out/bin/opencode
          '';

          meta = {
            description = "AI coding agent built for the terminal";
            homepage = "https://github.com/anomalyco/opencode";
            platforms = ["aarch64-darwin"];
          };
        };

    opencode-desktop =
      if useNixpkgs
      then prev.opencode-desktop
      else
        final.mkDarwinPackage rec {
          pname = "opencode-desktop";
          version = targetVersion;

          src = prev.fetchurl {
            url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-desktop-mac-arm64.zip";
            hash = "sha256-yjtxX1l1jE+F5jEPxjSrgILclWcGpsTp0GqM0VhWaD0=";
          };

          nativeBuildInputs = [prev.unzip];

          installPhase = ''
            mkdir -p $out/Applications $out/bin
            cp -r OpenCode.app $out/Applications/
            rm -f $out/Applications/OpenCode.app/Contents/Resources/app-update.yml
            ln -s $out/Applications/OpenCode.app/Contents/MacOS/OpenCode $out/bin/opencode-desktop
          '';

          meta = {
            description = "OpenCode Desktop App (auto-updater disabled)";
            homepage = "https://github.com/anomalyco/opencode";
            platforms = ["aarch64-darwin"];
          };
        };
  }
