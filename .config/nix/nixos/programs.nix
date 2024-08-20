# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {

  programs.mtr.enable = true;
  programs.fish.enable = true;
  programs.tmux.enable = true;
  programs.geary.enable = true;
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
  };

  # keep bash as the non-interactive shell, but use fish for interactive
  # sessions...for more info see https://nixos.wiki/wiki/Fish
  programs.bash = {
    interactiveShellInit = ''
      if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
      then

        shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
        # exec ${pkgs.fish}/bin/fish $LOGIN_OPTION

        # gnome-session... tells us that gdm is up and no user is logged
        # in sitting at the machine, in which case gnome-session-inhibit will
        # error out, effectively blocking incoming SSH connections

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
      fi
    '';
  };

}
