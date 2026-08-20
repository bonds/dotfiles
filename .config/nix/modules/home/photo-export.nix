{
  config,
  lib,
  pkgs,
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

  config = lib.mkIf cfg.enable {
    home.packages = [(pkgs.callPackage ../../pkgs/photokit-export {})];
  };
}
