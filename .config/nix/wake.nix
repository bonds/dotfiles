{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}:

{
  systemd.services.wakeusb = {
    serviceConfig = {
      Description = "Reset USB devices on wake from sleep";
      # Type = "";
      # User = "root";
      ExecStartPre = "/run/current-system/sw/bin/sleep 10";
      ExecStart = "/run/current-system/sw/bin/sh -c '/run/current-system/sw/bin/rmmod xhci_pci; /run/current-system/sw/bin/modprobe xhci_pci'";
    };
    after = [
      "suspend.target"
      "hibernate.target"
      "hybrid-sleep.target"
      "suspend-then-hibernate.target"
    ];
    wantedBy = [
      "suspend.target"
      "hibernate.target"
      "hybrid-sleep.target"
      "suspend-then-hibernate.target"
    ];
  };
}
