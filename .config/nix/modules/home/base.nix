{...}: {
  home.stateVersion = "26.05";

  imports = [
    ./tmux.nix
    ./what-changed.nix
  ];

  programs.what-changed.enable = true;
}
