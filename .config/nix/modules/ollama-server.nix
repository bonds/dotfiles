{
  config,
  lib,
  pkgs-unstable,
  ...
}: let
  cfg = config.services.ollama-server;
in {
  options.services.ollama-server = {
    enable = lib.mkEnableOption "shared ollama server config (enable + package)";
  };

  config = lib.mkIf cfg.enable {
    services.ollama = {
      enable = true;
      package = pkgs-unstable.ollama;
    };
  };
}
