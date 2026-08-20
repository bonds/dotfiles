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

    settings = lib.mkOption {
      type = lib.types.submodule {
        options = {
          destDir = lib.mkOption {
            type = lib.types.str;
            default = "/tmp/sophrosyne-photos";
            description = "Destination root next to the nightly SMB mount";
          };
          limit = lib.mkOption {
            type = lib.types.int;
            default = 0;
            description = "Max assets to export per run (0 = unlimited)";
          };
        };
      };
      default = {};
      description = "Written to ~/Library/Application Support/photo-export/config.toml; the app reads this because `open --args` doesn't reliably forward args to LaunchServices-registered apps.";
    };
  };

  config = lib.mkIf cfg.enable (let
    pkg = pkgs.callPackage ../../pkgs/photokit-export {};
    s = cfg.settings;
  in {
    home.packages = [pkg];

    # NOTE: no manual symlink/lsregister — Home Manager's built-in app
    # installer copies the bundled .app to "Applications/Home Manager Apps"
    # automatically, and that's the copy LaunchServices/`open` resolve to.
    # A manual symlink would SHADOW it with a stale bundle. The TCC Photos
    # grant follows the signed bundle identifier (com.ggr.photo-export), so
    # the HM-managed copy is the correct identity target.

    home.file."Library/Application Support/photo-export/config.toml".source = let
      format = pkgs.formats.toml {};
    in
      format.generate "config.toml" {
        dest = s.destDir;
        limit = s.limit;
      };
  });
}
