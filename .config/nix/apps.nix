{
  outputs,
  pkgs,
  ...
}:

{

  nixpkgs = {
    overlays = [
      outputs.overlays.unstable-packages
    ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    libnotify
    linuxKernel.packages.linux_zen.xone
    localsend
    coppwr
    pwvucontrol
    easyeffects
    noise-repellent
    cargo
    rust-script
    xclip
    rocmPackages.rocminfo
    usb-reset
    rlwrap
    idris2
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
    pstree
    idris2
    ghc
    ffmpeg
    nms
    bc
    atuin
    socat
    zed-editor
    gnome.dconf-editor
    dconf2nix
    obs-studio
    usbview
    fastfetch # system info on cli
    gsound # for pano
    libgda6 # for pano
    gnomeExtensions.easyeffects-preset-selector
    gnomeExtensions.pano # this is pano
    unstable.gnomeExtensions.another-window-session-manager
    gnomeExtensions.dash-to-panel
    jq
    libsecret
    jless
    unzip
    helix
    spotify
    discord
    slack
    signal-desktop
    ulauncher
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
