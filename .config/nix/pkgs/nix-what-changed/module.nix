{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.what-changed;
in {
  options.programs.what-changed = {
    enable = mkEnableOption "what-changed — show changelog summaries after nix rebuilds";

    settings = mkOption {
      type = types.submodule {
        options = {
          backend = mkOption {
            type = types.enum ["ollama" "openai"];
            default = "ollama";
            description = "LLM backend to use for summarization";
          };
          host = mkOption {
            type = types.str;
            default = "http://localhost:11434";
            description = "LLM API host";
          };
          model = mkOption {
            type = types.str;
            default = "qwen2.5:1.5b";
            description = "LLM model name";
          };
          timeout = mkOption {
            type = types.int;
            default = 40;
            description = "LLM request timeout in seconds";
          };
          maxInputBytes = mkOption {
            type = types.int;
            default = 15000;
            description = "Max changelog bytes sent to LLM";
          };
          maxBullets = mkOption {
            type = types.int;
            default = 5;
            description = "Max bullet points per summary";
          };
        };
      };
      default = {};
      description = "Settings written to ~/.config/what-changed/config.toml";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.what-changed];
    environment.etc."what-changed/config.toml".text = let
      s = cfg.settings;
    in ''
      backend = "${s.backend}"
      host = "${s.host}"
      model = "${s.model}"
      timeout = ${toString s.timeout}
      max_input_bytes = ${toString s.maxInputBytes}
      max_bullets = ${toString s.maxBullets}
    '';
  };
}
