_: {
  home.file = {
    ".config/sleepwatcher/common.sh" = {
      source = ./sleepwatcher/common.sh;
      force = true;
    };
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
