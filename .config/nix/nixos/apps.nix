{
  pkgs,
  inputs,
  ...
}:

{
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # kdePackages.kajongg # mahjong for real
    chromium # web browser
    unstable.ghostty # terminal
    todoist # todo list cli
    todoist-electron # todo list gui
    gapless # music player
    lollypop # music player
    resonance # music player
    spot # minimal spotify player
    tagger # edit tags in music files
    jujutsu # git competitor
    delta # git delta syntax highlighter
    whatsapp-for-linux # chat client
    unstable.python312Packages.python-kasa
    uefitool # get info from uefi images
    gamescope # compositor for steam games
    yubioath-flutter # gui for managing yubikey
    coreutils # for timeout for athome script
    kakoune # editor with support for editorconfig
    zulip # thread chat like slack but better?
    ventoy-full # gui for iso installer tool
    resources # pretty cpu usage visualizer
    keeweb # keepass password manager gui?
    speedtest-cli # to see how fast my internet is from the cli
    moreutils # so I can lookup errno
    amberol # gui music player
    apostrophe # gui markdown editor
    dig # cli dns lookups
    nodejs # javascript runtime environment
    # alacritty # a terminal
    # kitty # a terminal
    gcc # c compiler
    libreoffice # office suite
    # onlyoffice-bin # office suite
    glxinfo # gpu information
    newsflash # gui rss reader
    libresprite # animated sprite editor and pixel art tool
    # aseprite # animated sprite editor and pixel art tool
    unstable.mailspring # nice looking gui mail client
    inputs.nixos-conf-editor.packages.${system}.nixos-conf-editor
    element-desktop # irc chat client
    # yubikey-manager-qt # gui for configuring yubikey settings
    age-plugin-yubikey # yubikey support for age
    passage # cli password store using age
    rage # cli encryption, rust version
    # inputs.agenix.packages.${system}.default
    distrobox # virtualize other linux distros on top of this one
    monophony # youtube music player
    kdePackages.audiotube # youtube music player
    zenity # display a dialog box in gnome
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
    gimp # graphics editor
    krita # pixel art editor
    glmark2 # 3D benchmark for gpus
    radeontop # top for radeon gpus
    nix-search-cli # fast cli search for nix packages
    cpu-x # cli cpu, gpu, and motherboard hardware info
    bsd-finger # old school finger utility to get info on fellow users
    weather # cli weather app
    foliate # ebook reader
    fzf # fuzzy match text
    pstree # process list formatted as a tree
    idris2 # idris2 compiler
    cabal-install # build tool and dependency manager for haskell
    ghc # haskell compiler
    ffmpeg # video converter
    nms
    bc # calculator for scripts
    atuin # tool for managing terminal command history
    socat # needed for bin/wol script
    # zed-editor # another cli text editor
    dconf-editor
    dconf2nix # convert dconf dumps to nix format
    obs-studio # video capture and streaming
    usbview # gui directory of usb devices
    fastfetch # system info on cli
    gsound # for pano
    libgda6 # for pano
    gnomeExtensions.easyeffects-preset-selector
    gnomeExtensions.pano # clipboard manager
    unstable.gnomeExtensions.another-window-session-manager
    gnomeExtensions.dash-to-panel
    jq # cli json parser and pretty printer
    libsecret # cli for gnome passwords
    jless
    unzip # cli to decompress archives
    helix # cli text editor
    spotify # music subscription service gui
    discord # chat for games
    slack # chat for work
    signal-desktop # chat with good security
    # ulauncher # app launcher
    unstable.ollama # cli to run LLMs locally
    gnome-tweaks # gui for changing less common gnome settings
    wmctrl # cli for controlling windows in wayland
    # protonmail-desktop # email client for proton service
    obsidian # markdown based note taking
    dwarf-fortress # rogue-like resource management game
    git # version control system that everyone uses
    starship # terminal prompt made pretty
    lsd # ls with colors and folder icons
    ripgrep # fast grep written in rust
    fd # fast find written in rust
    nerdfonts # fonts with all the symbols added
    hyperfine # benchmarking tool
    sysbench # unix system benchmark
    zoom-us # proprietary video conferencing
    desktop-file-utils
    btop # better looking top
    rustc # rust compiler
    wget # cli http request tool
    usbutils # cli usb tools like usbreset
  ];
}
