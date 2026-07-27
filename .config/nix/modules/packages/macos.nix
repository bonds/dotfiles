{
  pkgs,
  inputs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    age-plugin-yubikey # age encryption with YubiKey support
    angband # best cli game ever
    bun # javascript runtime
    caffeine # don't go to sleep
    clamav # antivirus
    cloc # count lines of code
    coconutbattery # battery health monitor
    colima # docker for mac
    coreutils # for timeout for athome script
    cowsay # cli to print stuff with a pic of a cow saying it
    daisydisk # disk usage visualizer
    delta # git delta syntax highlighter
    discord # voice and text chat
    docker # docker
    duti # set default file handlers for macOS
    flux # blue light filter for sleep
    fortune # random quotes
    google-cloud-sdk # google cloud CLI and friends
    hugo # blog engine
    ice-bar # menu bar organizer
    idris2Packages.idris2Lsp # language service provider for idris2
    idris2Packages.pack # packages manager for idris2
    inputs.neocode.packages.${pkgs.stdenv.hostPlatform.system}.default # Native macOS SwiftUI client for OpenCode (community, flake, nr --update)
    inputs.polyptych.packages.${pkgs.stdenv.hostPlatform.system}.default # spanned fullscreen video player
    jujutsu # git alternative
    libreoffice-bin # office suite
    lima # vms for mac
    mpv # minimalist media player
    mtr # better traceroute
    nh # nix helper for rebuilds and garbage collection (darwin, no programs.nh module)
    nodejs # needed for hihello development
    opencode # AI coding agent (CLI, binary overlay, nr --update)
    opencode-desktop # OpenCode Electron desktop app (binary overlay, auto-updater disabled)
    osaurus # native macOS AI agent harness (binary overlay, nr --update)
    oxillama # pure Rust LLM inference engine (experimental, pkgs/oxillama/update.sh, nr --update)
    openssh # macos ssh doesn't come with resident ssh support
    osxphotos # export photos from Apple Photos app
    passage # age-based password manager
    (pkgs.callPackage ../../pkgs/ghosttile {}) # hide apps from Dock/Cmd+Tab
    (python3.withPackages (p:
      with p; [
        python-kasa # control TP-Link smart home devices
      ]))
    rage # encryption tool (age alternative)
    rustup # rust installer
    syncthing # peer-to-peer file synchronization
    tailscale # tailnet CLI
    the-powder-toy # physics simulation game
    typescript # javascript dialect
    utm # virtual machine manager for macOS
    whisper-cpp # cli tool for converting audio to text
    xclip # for copying from terminal to clipboard
    yt-dlp # download videos from YouTube and more
    zen-browser # firefox fork with vertical tabs
  ];
}
