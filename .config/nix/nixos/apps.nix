{
  pkgs,
  inputs,
  ...
}:

{
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    yubioath-flutter
    yubikey-manager-qt # gui for configuring yubikey settings
    age-plugin-yubikey # yubikey support for age
    passage # cli password store using age
    rage # cli encryption, rust version
    inputs.agenix.packages.${system}.default
    distrobox # virtualize other linux distros on top of this one
    monophony # youtube music player
    kdePackages.audiotube
    gnome.zenity # display a dialog box in gnome
    libnotify # display a gnome notification
    linuxKernel.packages.linux_zen.xone # xbox controller driver
    localsend # send files to others on the LAN like AirPlay
    # coppwr
    # pwvucontrol
    easyeffects # audio effects mixer and router
    noise-repellent
    cargo # library installer for rust
    rust-script # create scripts using rust
    xclip # copy stuff to xclipboard via cli
    rocmPackages.rocminfo
    usb-reset # reset specific USB devices
    rlwrap # wrapper for cli apps that adds history, used for idris2
    idris2 # compiler for the ML family language
    gimp
    krita
    glmark2
    radeontop
    nix-search-cli
    cpu-x
    bsd-finger
    weather
    foliate # ebook reader
    fzf
    pstree # process list formatted as a tree
    idris2 # idris2 compiler
    ghc # haskell compiler
    ffmpeg # video converter
    nms
    bc # calculator for scripts
    atuin # tool for managing terminal command history
    socat # needed for bin/wol script
    zed-editor
    gnome.dconf-editor
    dconf2nix
    obs-studio
    usbview
    fastfetch # system info on cli
    gsound # for pano
    libgda6 # for pano
    gnomeExtensions.easyeffects-preset-selector
    gnomeExtensions.pano # clipboard manager
    unstable.gnomeExtensions.another-window-session-manager
    gnomeExtensions.dash-to-panel
    jq # cli json parser and pretty printer
    libsecret
    jless
    unzip
    helix # cli text editor
    spotify # music subscription service gui
    discord # chat for games
    slack # chat for work
    signal-desktop # chat with good security
    ulauncher # app launcher
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
    zoom-us
    desktop-file-utils
    btop
    rustc
    wget
    usbutils
  ];
}
