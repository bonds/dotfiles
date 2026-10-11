# Shared NixOS settings for sophrosyne and metanoia.
{
  config,
  pkgs,
  lib,
  ...
}: let
  pruneGenerations = import ./prune-generations.nix {inherit pkgs;};
in {
  # NixOS-specific nix settings
  nix.settings.auto-allocate-uids = lib.mkDefault true;
  nix.settings.use-cgroups = lib.mkDefault true;

  time.timeZone = "America/Los_Angeles";

  i18n.defaultLocale = "en_US.UTF-8";

  # Common module list: lib/shared-modules.nix (wired via mkNixos).

  programs = {
    command-not-found.enable = false;

    tmux.enable = lib.mkDefault true;
    nh = {
      enable = lib.mkDefault true;
      flake = lib.mkDefault "${config.users.users.scott.home}/.config/nix";
    };
  };
  services.fstrim.enable = lib.mkDefault true;

  security.sudo.enable = lib.mkDefault false;
  security.doas.enable = lib.mkDefault true;

  # Wheel users may escalate with a persisted credential. `scott ∈ wheel`, so a
  # per-user persist rule is redundant — do not re-add `users = ["scott"]`
  # (nix-config-review.md F4).
  security.doas.extraRules = [
    {
      users = [":wheel"];
      persist = true;
    }
  ];

  services.openssh = {
    enable = lib.mkDefault true;
    settings = {
      PermitRootLogin = lib.mkDefault "no";
      PasswordAuthentication = lib.mkDefault false;
      AllowAgentForwarding = lib.mkDefault true;
    };
  };

  # Started ONLY by the weekly timer below. Do NOT add `wantedBy` here: a
  # `wantedBy = ["timers.target"]` on the *service* pulls it in at every boot
  # (timers.target is reached at boot), which defeats the weekly schedule. Only
  # the timer is `wantedBy` timers.target (nix-config-review.md F8).
  systemd.services.prune-generations = {
    description = "Prune old nix system profile generations";
    after = ["nix-daemon.service"];
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
