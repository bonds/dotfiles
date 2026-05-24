{
  config,
  pkgs,
  lib,
  self,
  ...
}: {
  # https://github.com/nix-darwin/nix-darwin?tab=readme-ov-file#prerequisites

  # List packages installed in system profile. To search by name, run:
  # $ nix search nixpkgs wget
  environment.systemPackages = with pkgs; [
    smartmontools # for smartctl
    pv # for watching progress
    watch # for running scripts in a loop
    xclip # for copying from terminal to clipboard
    alejandra # nix code formatter
    tokei # like cloc but uses treesitteng to count tokens
    opencode # like claude code but open source
    openssh # macos ssh doesn't come with resident ssh support
    ollama
    jan
    utm
    flux
    discord
    daisydisk
    coconutbattery
    # turbo # javascript runtime
    gh # github cli tool
    bun # javascript runtime
    typescript # javascript dialect
    google-cloud-sdk # google cloud CLI and friends
    jujutsu # git alternative
    cloc # count lines of code
    nodejs # needed for hihello development
    whisper-cpp # cli tool for converting audio to text
    yt-dlp # youtube downloader
    angband # best cli game ever
    rustup # rust installer
    autokbisw # switch layout based on which keyboard is plugged in
    ice-bar # menu bar organizer
    clamav # antivirus
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
    speedtest-cli # benchmark for internet speeds
    nh # improved darwin-rebuild ui
    coreutils # for timeout for athome script
    hugo # blog engine
    libreoffice-bin # office suite
    rage
    element-desktop
    docker # docker
    colima # docker for mac
    jq # json parser
    weather # cli weather report
    mtr # better traceroute
    age-plugin-yubikey
    passage
    atuin # pretty terminal history
    fzf # fast fuzzy matching
    socat
    btop # pretty top
    lsd # pretty ls
    fd # faster find
    ripgrep # faster grep
    sysbench # cli benchmark
    hyperfine # cli benchmark
    fastfetch
    starship # terminal prompt pretty formatting
    rlwrap # command line wrapper for idris2
    idris2Packages.idris2Lsp # language service provider for idris2
    idris2Packages.pack # packages manager for idris2
    idris2 # functional language
    helix # better cli text editor
    (python3.withPackages (p:
      with p; [
        python-kasa
      ]))
  ];

  security.pam.services.sudo_local.touchIdAuth = true;

  # Set Git commit hash for darwin-version.
  system.configurationRevision = self.rev or self.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 6;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  # add a font so libreoffice docs look the same across mac and linux
  fonts.packages = with pkgs; [
    helvetica-neue-lt-std
  ];

  users.users.scott.home = "/Users/scott";
  users.users.scott.shell = pkgs.fish;
  system.primaryUser = "scott";

  # https://www.danielcorin.com/til/nix-darwin/launch-agents/
  launchd = {
    user = {
      agents = {
        ollama-serve = {
          command = "${pkgs.ollama}/bin/ollama serve";
          serviceConfig = {
            KeepAlive = true;
            RunAtLoad = true;
            StandardOutPath = "/tmp/ollama.out.log";
            StandardErrorPath = "/tmp/ollama.err.log";
          };
        };
      };
    };
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "old";
    users.scott = {pkgs, ...}: {
      home.stateVersion = "24.11";
      home.homeDirectory = "/Users/scott";
      programs.fish.plugins = with pkgs.fishPlugins; [fzf-fish];
    };
  };
}
