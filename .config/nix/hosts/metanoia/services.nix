{
  config,
  pkgs,
  lib,
  ...
}: let
  userHome = import ../../lib/user-home.nix pkgs;
in {
  services.printing.enable = true;

  services.ollama-server.enable = true;
  systemd.services.ollama.serviceConfig.Restart = lib.mkForce "always";

  services.fprintd.enable = true;

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  services.syncthing = {
    enable = true;
    user = "scott";
    dataDir = "${userHome}/Documents";
    configDir = "${userHome}/.config/syncthing";
  };
  systemd.services.syncthing.environment.STNODEFAULTFOLDER = "true";

  services.pcscd.enable = true;
  services.irqbalance.enable = true;
  services.fwupd.enable = true;
  hardware.xone.enable = true;

  powerManagement.powerDownCommands = lib.mkAfter ''
    systemctl stop vuclient.service
    sleep 1
  '';

  systemd.services.nix-daemon = {
    environment.TMPDIR = "/var/tmp";
  };

  systemd.services.vuclient-wake = {
    description = "Restart vuclient after resume from sleep";
    after = ["sleep.target"];
    wantedBy = ["sleep.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/systemctl start vuclient.service";
    };
  };

  systemd.services.wakeusb = {
    serviceConfig = {
      Description = "Reset USB devices on wake from sleep";
      ExecStartPre = "/run/current-system/sw/bin/sleep 1";
      ExecStart = "/run/current-system/sw/bin/sh -c '/run/current-system/sw/bin/rmmod hid_magicmouse; /run/current-system/sw/bin/modprobe hid_magicmouse'";
      Type = "oneshot";
    };
    after = ["sleep.target"];
    wantedBy = ["sleep.target"];
  };

  systemd.tmpfiles.rules = [
    "L+ /run/gdm/.config/monitors.xml - - - - ${pkgs.writeText "gdm-monitors.xml" (builtins.readFile ./monitors.xml)}"
  ];

  systemd.user.services.ulauncher = {
    wantedBy = ["graphical-session.target"];
    partOf = ["graphical-session.target"];
    unitConfig = {
      Description = "Linux Application Launcher";
      Documentation = ["https://ulauncher.io/"];
    };
    environment = let
      pydeps = pkgs.python3.withPackages (pp:
        with pp; [
          google
          pytz
          pint
          simpleeval
          requests
          parsedatetime
          google-api-python-client
          google-auth-oauthlib
          pydbus
          pygobject3
        ]);
    in {
      PYTHONPATH = "${pydeps}/${pydeps.sitePackages}";
    };
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 1;
      ExecStart = pkgs.writeShellScript "ulauncher-env-wrapper.sh" ''
        export PATH="''${XDG_BIN_HOME}:$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
        export GDK_BACKEND=x11
        exec ${pkgs.ulauncher}/bin/ulauncher --hide-window
      '';
    };
  };
}
