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
    agenix.packages.x86_64-linux.default
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
