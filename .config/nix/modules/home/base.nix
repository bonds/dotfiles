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
      host = "http://sophrosyne:8080";
      model = "qwen2.5-7b";
      timeout = 300;
    };
  };
}
