{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.what-changed;
in {
  imports = [./options.nix];

  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.what-changed];
    environment.etc."what-changed/config.toml".source = let
      format = pkgs.formats.toml {};
      s = cfg.settings;
    in
      format.generate "config.toml" {
        backend = s.backend;
        host = s.host;
        model = s.model;
        timeout = s.timeout;
        max_input_bytes = s.maxInputBytes;
        max_bullets = s.maxBullets;
        prompt_style = s.promptStyle;
      };
  };
}
