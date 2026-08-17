{...}: {
  home.stateVersion = "26.05";

  imports = [
    ./ghostty.nix
    ./tmux.nix
    ./what-changed.nix
  ];

  programs.what-changed = {
    enable = true;
    settings = {
      backend = "openai";
      host = "http://100.85.189.110:8080";
      model = "qwen2.5-7b";
    };
  };
}
