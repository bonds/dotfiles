{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}:

{
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    helix
    spotify
    discord
    slack
    signal-desktop
    ulauncher
    neofetch
    ollama
    gnome.gnome-tweaks
    wmctrl
    protonmail-desktop
    obsidian
    dwarf-fortress
    git
    starship
    lsd
    ripgrep
    fd
    nerdfonts
    hyperfine
    sysbench
    zoom
    desktop-file-utils
  ];
}
