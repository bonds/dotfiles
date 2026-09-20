{...}: {
  home.file = {
    ".config/sleepwatcher/sleep.sh" = {
      source = ./sleepwatcher/sleep.sh;
      executable = true;
      force = true;
    };
    ".config/sleepwatcher/wake.sh" = {
      source = ./sleepwatcher/wake.sh;
      executable = true;
      force = true;
    };
  };
}
