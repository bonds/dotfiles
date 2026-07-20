{...}: {
  home.stateVersion = "26.05";

  imports = [
    ./ghostty.nix
    ./tmux.nix
    ./what-changed.nix
  ];

  programs.what-changed.enable = true;
}
