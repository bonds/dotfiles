{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.bash-to-fish;
in {
  options.modules.bash-to-fish = {
    enable = lib.mkEnableOption "bash-to-fish exec wrapper";
    gnome-inhibit = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable gnome-session-inhibit wrapper for SSH sessions (metanoia only)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    programs.bash.interactiveShellInit = ''
      if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
      then
        shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
        ${
        if cfg.gnome-inhibit.enable
        then ''
          if test -z "$SSH_CONNECTION" || ! gnome-session-inhibit --list > /dev/null 2>&1; then
            exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
          else
            from=$(echo $SSH_CONNECTION | awk '{print $1}')
            to=$(echo $SSH_CONNECTION | awk '{print $3}')
            exec gnome-session-inhibit \
                --app-id $USER@ggr.com \
                --inhibit suspend \
                --reason "SSHed into $(hostname) from $from at $(date '+%F %T')" \
                ${pkgs.fish}/bin/fish $LOGIN_OPTION
          fi
        ''
        else ''
          exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
        ''
      }
      fi
    '';
  };
}
