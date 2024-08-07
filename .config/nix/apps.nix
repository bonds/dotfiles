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
