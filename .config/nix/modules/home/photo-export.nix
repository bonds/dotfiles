{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.programs.photo-export;
in {
  options.programs.photo-export = {
    enable = lib.mkEnableOption "photo-export — PhotoKit-native iCloud photo downloader (replaces osxphotos --download-missing)";

    manifestPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.cache/photo-export-manifest.txt";
      description = "State file tracking already-exported photo UUIDs for resumable runs";
    };
  };

  config = lib.mkIf cfg.enable (let
    pkg = pkgs.callPackage ../../pkgs/photokit-export {};
  in {
    home.packages = [pkg];

    # Symlink .app into ~/Applications + register with LaunchServices so
    # `open photo-export` and open-from-Finder work at a stable path.
    # (nix-store paths change per rebuild; the TCC Photos grant follows the
    # signed bundle identifier, but the *path* must stay stable for open.)
    home.activation.registerPhotoExport = config.lib.dag.entryAfter ["writeBoundary"] ''
      STORE="${pkg}"
      APP="$STORE/Applications/photo-export.app"
      DEST="$HOME/Applications/photo-export.app"
      mkdir -p "$HOME/Applications"
      if [ -e "$DEST" ] || [ -L "$DEST" ]; then rm -rf "$DEST"; fi
      ln -sfn "$APP" "$DEST"
      if [ -d "$DEST" ]; then
        LOG() { echo "[photo-export] $*" >&2; }
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" 2>&1 || LOG "lsregister failed (exit $?)"
      fi
    '';
  });
}
