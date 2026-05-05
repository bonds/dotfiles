{
  inputs,
  outputs,
  config,
  pkgs,
  lib,
  ...
}: {
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [outputs.overlays.unstable-packages];
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = with pkgs; [
    turbo
    gh
    bun
    typescript
    node2nix
    google-cloud-sdk # google cloud CLI and friends
    jujutsu # git alternative
    cloc # count lines of code
    nodejs # needed for hihello development
    whisper-cpp # cli tool for converting audio to text
    yt-dlp # youtube downloader
    angband # best cli game ever
    rustup
    (python312.withPackages (p: with p; [tornado numpy pillow requests argparse pyyaml pyserial pyinstaller ruamel-yaml])) # for vuserver
    # python312Packages.qiskit # quantum sdk
    # open-webui # webui for ollama
    autokbisw # switch layout based on which keyboard is plugged in
    ice-bar # menu bar organizer
    clamav # antivirus
    # unstable.cargo # rust library downloader
    # unstable.rustc # rust compiler
    cowsay # cli to print stuff with a pic of a cow saying it
    fortune # random quotes
    cabal-install # haskell library installer
    ghc # haskell compiler
    delta # git delta syntax highlighter
    the-powder-toy # physics simulation game
    mpv # to watch videos in weird formats
    ffmpeg # convert videos
    rclone # for backups
    rsync # get latest version
    speedtest-cli
    unstable.nh # improved darwin-rebuild ui
    delta # diff pager for git
    coreutils # for timeout for athome script
    hugo # blog engine
    libreoffice-bin # office suite
    python311Packages.python-kasa
    rage
    # element-desktop
    unstable.ollama # not a service yet: https://github.com/LnL7/nix-darwin/pull/972
    docker
    colima
    jq
    weather
    mtr
    age-plugin-yubikey
    passage
    atuin
    fzf
    socat
    btop
    lsd
    fd
    ripgrep
    sysbench
    hyperfine
    starship
    rlwrap # command line wrapper for idris2
    idris2Packages.idris2Lsp # language service provider for idris2
    idris2Packages.pack # packages manager for idris2
    idris2
    alacritty
    helix
    vim
  ];

  environment.customIcons = {
    enable = true;
    icons = [
      {
        path = "/Applications/Nix Apps/Alacritty.app";
        icon = "/Users/scott/Documents/terminal.icns";
      }
      {
        path = "/Users/scott/Applications/Alacritty";
        icon = "/Users/scott/Documents/terminal.icns";
      }
    ];
  };

  # launchd.user.agents.ollama = {
  #   enabled = true;
  #   serviceConfig = {
  #     ProgramArguments = [
  #       "${cfg.package}/bin/${cfg.exec}" "server"
  #     ];
  #     KeepAlive = true;
  #     RunAtLoad = true;
  #   };
  # };

  # Auto upgrade nix package and the daemon service.
  # services.nix-daemon.enable = true;
  # nix.package = pkgs.nix;

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true; # default shell on catalina
  programs.fish.enable = true;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 5;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  nix = {
    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";

      # Opinionated: disable global registry
      # flake-registry = "";

      # Workaround for https://github.com/NixOS/nix/issues/9574
      nix-path = config.nix.nixPath;

      # don't keep telling me when my nix config hasn't been committed
      # to the git repro yet, I don't care!
      # https://git.2li.ch/Nebucatnetzer/nixos/commit/36d3953121d968191cd5d83cab201af70e6c864
      warn-dirty = false;
    };

    # Opinionated: disable channels
    channel.enable = false;
  };

  # add a font so libreoffice docs look the same across mac and linux
  fonts.packages = with pkgs; [
    helvetica-neue-lt-std
    # sf-mono-liga-bin
  ];
}
