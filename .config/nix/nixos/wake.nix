{
  systemd,
  ...
}:

{
  systemd.services.wakeusb = {
    serviceConfig = {
      Description = "Reset USB devices on wake from sleep";
      ExecStartPre = "/run/current-system/sw/bin/sleep 1";
      ExecStart = "/run/current-system/sw/bin/sh -c '/run/current-system/sw/bin/rmmod xhci_pci; /run/current-system/sw/bin/modprobe xhci_pci'";
      # ExecStartPost = "/run/current-system/sw/bin/sleep 10";
      Type = "oneshot";
    };
    after = [
      "sleep.target"
    ];
    wantedBy = [
      "sleep.target"
    ];
  };
}
