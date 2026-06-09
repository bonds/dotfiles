{pkgs, ...}: {
  programs.tmux = {
    enable = true;

    shortcut = "b";
    baseIndex = 1;
    historyLimit = 10000;
    mouse = true;
    keyMode = "vi";
    escapeTime = 0;

    plugins = [
      {
        # CAUTION: @catppuccin_* opts MUST go in plugin.extraConfig (runs before
        # run-shell), NOT in programs.tmux.extraConfig (runs after plugin loads).
        plugin = pkgs.tmuxPlugins.catppuccin;
        extraConfig = ''
          set -g @catppuccin_flavor 'frappe'
          set -g @catppuccin_window_status_style 'rounded'
        '';
      }
      pkgs.tmuxPlugins.cpu
      pkgs.tmuxPlugins.battery
    ];

    extraConfig = ''
      # Truecolor
      set -ag terminal-features "xterm-256color:truecolor"
      set -g default-terminal "tmux-256color"

      # Status bar modules (catppuccin recommended layout)
      set -g status-right-length 100
      set -g status-left-length 100
      set -g status-left ""
      set -g status-right "#{E:@catppuccin_status_application}"
      set -agF status-right "#{E:@catppuccin_status_cpu}"
      set -agF status-right "#{E:@catppuccin_status_ram}"
      set -ag status-right "#{E:@catppuccin_status_session}"
      set -ag status-right "#{E:@catppuccin_status_uptime}"
      set -agF status-right "#{E:@catppuccin_status_battery}"

      # Easier splits
      bind | split-window -h
      bind - split-window -v

      # Vim movement between panes
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      # Easier reload
      bind r source-file ~/.config/tmux/tmux.conf \; display "Reloaded!"
    '';
  };
}
