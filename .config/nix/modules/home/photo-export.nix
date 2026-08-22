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
          selfmount = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Let photo-export mount the SMB share itself (NetFS) when dest is the mount path, instead of requiring an external expect mount. Enables launching via `open` with no wrapper.";
          };
          # SFTP transport (Option A): stream originals in-memory to a remote
          # host over SFTP (no local temp copy, no SSD wear). When remoteHost is
          # set, photo-export uses the restricted id_photo_rsync key to stream to
          # the remote base (the rrsync-photos wrapper confines it to
          # /dragon/media/photos/). Mutually exclusive with SMB mount.
          remoteHost = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Set to push over SFTP instead of SMB (e.g. \"sophrosyne.local\" or MagicDNS). Empty = SMB transport.";
          };
          remoteUser = lib.mkOption {
            type = lib.types.str;
            default = "photo-backup";
            description = "SFTP user to write /dragon/media/photos (photo-backup owns the tree; its authorized_keys holds the SFTP-restricted photo-rsync key).";
          };
          remoteKey = lib.mkOption {
            type = lib.types.path;
            default = "${config.home.homeDirectory}/.ssh/id_photo_rsync";
            description = "No-passphrase SSH key authorized on the remote for the rrsync-photos wrapper.";
          };
          remoteBase = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Base path on the remote (relative to the wrapper's confined /dragon/media/photos). Empty = photos root.";
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
        selfmount = s.selfmount;
        remoteHost = s.remoteHost;
        remoteUser = s.remoteUser;
        remoteKey = s.remoteKey;
        remoteBase = s.remoteBase;
      };
  });
}
