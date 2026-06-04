{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    bat # cat clone with syntax highlighting
    btop # system resource monitor (top alternative)
    fastfetch # system info display tool
    fd # fast and user-friendly find alternative
    ffmpeg # multimedia converter and streamer
    fzf # fuzzy finder for files, history, etc.
    git # distributed version control
    hyperfine # command-line benchmarking tool
    jq # lightweight JSON processor
    lsd # ls with icons, colors, and tree view
    moreutils # additional Unix utilities (sponge, etc.)
    pstree # display running processes as a tree
    pv # monitor data progress through a pipe
    rclone # sync files to/from cloud storage
    rsync # fast incremental file transfer
    smartmontools # monitor disk health (S.M.A.R.T.)
    socat # multipurpose socket relay and pipe tool
    speedtest-cli # command-line internet speed test
    sysbench # system performance benchmark suite
    units # unit conversion calculator
    unzip # extract ZIP archives
    watch # execute a command periodically
    weather # command-line weather forecast
  ];
}
