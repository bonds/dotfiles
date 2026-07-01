# == Drive performance notes (WD Game Drive 5TB, WD50NMZW) ==
#
# USB VID:PID 1058:262f — Western Digital proprietary bridge, BOT (Bulk-Only Transport)
# only. No UASP support (bInterfaceProtocol 0x50, no alternate setting 0x62). USB-native
# PCB — cannot shuck or swap enclosure. QD=1 hardware limit.
#
# Sequential write (dd bs=1M, 5GB): ~40-90 MB/s on ext4, ~140-150 MB/s on exFAT
#   (ref: https://unix.stackexchange.com/questions/613223 — same WD NMZW drive family).
# ext4 journal enforces write ordering, serializing at QD=1. exFAT has no journal so it
# appears faster but offers no crash recovery and no POSIX perms (breaks rsync --archive).
#
# Random I/O (journal replay, dirty page flush): ~1 MB/s. With default dirty_ratio=20%
# on a 32GB system, umount can queue ~6.4 GB of dirty pages — a 73-minute wait at QD=1.
#
# Our fix: skip umount in cleanup() on SIGTERM (fast stop in ~1s), keep mount live,
# auto-resume via firesafe-backup-resume.timer (every 2 min). Progress tracking via
# .firesafe-progress skips completed sources on resume.
#
# Future speed options (not needed with fast-stop resume):
#   - `tune2fs -O ^has_journal /dev/sdX` — ~2x ext4 speed, lose crash recovery
#   - Reformat to exFAT — fastest, but no perms/ownership (rsync --archive breaks)
#   - Replace with a 3.5" SATA drive in UASP enclosure (ASMedia 1153e, RTL9210) — 100+ MB/s
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.programs.firesafe-backup;

  backupScript = import ./firesafe/backup.nix {inherit pkgs lib cfg;};
  statusScript = import ./firesafe/status.nix {inherit pkgs lib cfg;};
  reclaimScript = import ./firesafe/reclaim.nix {inherit pkgs lib cfg;};
  deletedScript = import ./firesafe/deleted.nix {inherit pkgs lib cfg;};
  ejectScript = import ./firesafe/eject.nix {inherit pkgs lib cfg;};
in {
  options.programs.firesafe-backup = {
    enable = lib.mkEnableOption "firesafe USB backup service";

    sources = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      example = {
        Archive = "/dragon/archive";
        Media = "/dragon/media";
      };
      description = "Attribute set mapping destination directory names to source paths.";
    };

    driveLabel = lib.mkOption {
      type = lib.types.str;
      default = "firesafe";
      description = "Filesystem label to identify the fire safe USB drive.";
    };

    mountPoint = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/firesafe";
      description = "Mount point for the fire safe USB drive.";
    };

    spaceThreshold = lib.mkOption {
      type = lib.types.int;
      default = 50;
      description = "Minimum free space in GB required before rsync starts.";
    };

    emailRecipient = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Email address for backup notifications (uses msmtp).";
    };

    excludes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["@eaDir" ".DS_Store" "Thumbs.db" ".zfs" "@tmp"];
      description = "rsync exclude patterns.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="${cfg.driveLabel}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="firesafe-backup.service"
    '';

    systemd.services.firesafe-backup = {
      description = "Firesafe USB backup";
      after = ["dev-disk-by\\x2dlabel-${cfg.driveLabel}.device"];
      wantedBy = [];
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${backupScript}";
        TimeoutStopSec = 7200;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
        Environment = "PATH=${pkgs.coreutils}/bin:${pkgs.util-linux}/bin:${pkgs.gnused}/bin:${pkgs.gnugrep}/bin:${pkgs.gawk}/bin";
      };
    };

    # Auto-resume: if the backup was interrupted (e.g. by `nr` rebuild), restart it.
    systemd.timers.firesafe-backup-resume = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "2min";
      };
    };

    systemd.services.firesafe-backup-resume = {
      description = "Resume firesafe backup if interrupted";
      # No after/wants — resume script conditionally starts backup via systemctl start
      script = ''
        set -e
        if ! mountpoint -q "${cfg.mountPoint}" 2>/dev/null; then
          exit 0
        fi
        if ! [ -f "${cfg.mountPoint}/.firesafe-backup-interrupted" ]; then
          exit 0
        fi
        if systemctl is-active firesafe-backup.service >/dev/null 2>&1; then
          exit 0
        fi
        # Also check: never resume if complete marker is newer than interrupted
        if [ -f "${cfg.mountPoint}/.firesafe-backup-complete" ] &&
           [ "${cfg.mountPoint}/.firesafe-backup-complete" -nt "${cfg.mountPoint}/.firesafe-backup-interrupted" ]; then
          exit 0
        fi
        touch /run/firesafe-resume
        systemctl start firesafe-backup.service
      '';
      serviceConfig = {
        Type = "oneshot";
        StandardOutput = "journal+console";
        Environment = "PATH=${pkgs.coreutils}/bin:${pkgs.systemd}";
      };
    };

    environment.systemPackages = [statusScript reclaimScript deletedScript ejectScript];

    systemd.tmpfiles.rules = [
      "f /var/log/firesafe-backup.log 0640 root users -"
    ];
  };
}
