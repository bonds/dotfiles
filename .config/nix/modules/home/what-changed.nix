{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.what-changed;
in {
  imports = [../../pkgs/nix-what-changed/options.nix];

  config = lib.mkIf cfg.enable {
    home.packages = [(pkgs.callPackage ../../pkgs/nix-what-changed {})];
    home.file.".config/what-changed/config.toml".source = let
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
