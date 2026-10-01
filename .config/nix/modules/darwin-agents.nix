{pkgs, ...}: let
  userHome = import ../lib/user-home.nix pkgs;
  pruneGenerations = import ./prune-generations.nix {inherit pkgs;};
in {
  # launchd user agents for accismus. Extracted from
  # hosts/accismus/configuration.nix so the host config stays readable.
  launchd.user.agents = {
    # --- Disabled 2026-08-04: moving to MCP on sophrosyne ---
    # llamacpp-serve = {
    #   command = "${llamacppServeScript}";
    #   serviceConfig = {
    #     KeepAlive = true;
    #     RunAtLoad = true;
    #     StandardOutPath = "${userHome}/Library/Logs/llamacpp.out.log";
    #     StandardErrorPath = "${userHome}/Library/Logs/llamacpp.err.log";
    #   };
    # };
    # llamacpp-vision-serve = {
    #   command = "${llamacppVisionServeScript}";
    #   serviceConfig = {
    #     KeepAlive = true;
    #     RunAtLoad = true;
    #     StandardOutPath = "${userHome}/Library/Logs/llamacpp-vision.out.log";
    #     StandardErrorPath = "${userHome}/Library/Logs/llamacpp-vision.err.log";
    #   };
    # };
    prune-generations = {
      command = "${pruneGenerations}/bin/prune-generations";
      serviceConfig = {
        StartCalendarInterval = [
          {
            Hour = 3;
            Minute = 0;
            Weekday = 0;
          }
        ];
        StandardOutPath = "${userHome}/Library/Logs/prune-generations.out.log";
        StandardErrorPath = "${userHome}/Library/Logs/prune-generations.err.log";
      };
    };
    photos-backup = {
      command = "${userHome}/bin/photos-backup";
      serviceConfig = {
        StartCalendarInterval = [
          {
            Hour = 2;
            Minute = 0;
          }
        ];
        StandardOutPath = "${userHome}/Library/Logs/photos-backup.out.log";
        StandardErrorPath = "${userHome}/Library/Logs/photos-backup.err.log";
      };
    };
    # SleepWatcher — eject the 'Extra Space' volume before sleep, remount on
    # wake (see ~/.config/sleepwatcher/{sleep,wake}.sh). Uses RunAtLoad +
    # KeepAlive so the agent persists as a login user agent.
    sleepwatcher = {
      serviceConfig = {
        ProgramArguments = [
          "${pkgs.sleepwatcher}/bin/sleepwatcher"
          "-V"
          "-s"
          "${userHome}/.config/sleepwatcher/sleep.sh"
          "-w"
          "${userHome}/.config/sleepwatcher/wake.sh"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "${userHome}/Library/Logs/sleepwatcher.out.log";
        StandardErrorPath = "${userHome}/Library/Logs/sleepwatcher.err.log";
      };
    };
  };
}
