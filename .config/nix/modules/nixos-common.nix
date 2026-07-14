# Shared NixOS settings for sophrosyne and metanoia.
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  pruneGenerations = import ./prune-generations.nix {inherit pkgs;};
in {
  # NixOS-specific nix settings
  nix.settings.auto-allocate-uids = lib.mkDefault true;
  nix.settings.use-cgroups = lib.mkDefault true;

  time.timeZone = "America/Los_Angeles";

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Provided by lib/common-modules.nix (wired via mkNixos).

  programs.command-not-found.enable = false;

  # Absorbed from per-host duplication (all with lib.mkDefault):
  programs.tmux.enable = lib.mkDefault true;
  programs.nh = {
    enable = lib.mkDefault true;
    flake = lib.mkDefault "${config.users.users.scott.home}/.config/nix";
  };
  services.fstrim.enable = lib.mkDefault true;

  security.sudo.enable = lib.mkDefault false;
  security.doas.enable = lib.mkDefault true;

  services.openssh = {
    enable = lib.mkDefault true;
    settings = {
      PermitRootLogin = lib.mkDefault "no";
      PasswordAuthentication = lib.mkDefault false;
      AllowAgentForwarding = lib.mkDefault true;
    };
  };

  systemd.services.prune-generations = {
    description = "Prune old nix system profile generations";
    after = ["nix-daemon.service"];
    wantedBy = ["timers.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pruneGenerations}/bin/prune-generations";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.prune-generations = {
    description = "Weekly nix generation pruning";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
