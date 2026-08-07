# https://jezenthomas.com/2026/07/nix-overrides-that-expire-themselves/
#
# Self-expiring override: when nixpkgs catches up to our target version,
# the warning fires and tells us to delete this overlay.
final: prev: let
  targetVersion = "4.34.2";
  useNixpkgs = prev.lib.versionAtLeast prev.daisydisk.version targetVersion;
in {
  daisydisk =
    prev.lib.warnIf useNixpkgs
    "daisydisk >= ${targetVersion} is now in nixpkgs, the overlay can be removed."
    (
      if useNixpkgs
      then prev.daisydisk
      else
        final.mkDarwinPackage {
          pname = "daisydisk";
          version = targetVersion;

          src = prev.fetchurl {
            url = "https://daisydiskapp.com/download/DaisyDisk.zip";
            hash = "sha256-Re9GOfK03Gogb4Ep1itUJm60L94qvGfXgjqpLg8GQlc=";
          };

          nativeBuildInputs = [prev.unzip];

          installPhase = ''
            mkdir -p $out/Applications
            cp -r DaisyDisk.app $out/Applications/
          '';

          meta = {
            description = "Disk usage visualizer with a pie chart interface";
            homepage = "https://daisydiskapp.com";
            license = prev.lib.licenses.unfree;
          };
        }
    );
}
