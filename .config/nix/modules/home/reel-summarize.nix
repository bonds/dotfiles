{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.reel-summarize;
in {
  options.programs.reel-summarize = {
    enable = lib.mkEnableOption "reel-summarize — summarize Instagram Reels using local models";

    settings = lib.mkOption {
      type = lib.types.submodule {
        options = {
          host = lib.mkOption {
            type = lib.types.str;
            default = "http://localhost:11434";
            description = "Ollama API host";
          };
          visionModel = lib.mkOption {
            type = lib.types.str;
            default = "llama3.2-vision:11b";
            description = "Ollama vision model for per-frame OCR";
          };
          summarizeModel = lib.mkOption {
            type = lib.types.str;
            default = "qwen2.5:7b";
            description = "Ollama model for final summary";
          };
          whisperModel = lib.mkOption {
            type = lib.types.str;
            default = "small";
            description = "Whisper model size (tiny, base, small, medium, large-v3)";
          };
          framesPerSecond = lib.mkOption {
            type = lib.types.int;
            default = 1;
            description = "Frame sampling rate";
          };
          maxFrames = lib.mkOption {
            type = lib.types.int;
            default = 60;
            description = "Maximum frames to analyze";
          };
        };
      };
      default = {};
      description = "Settings written to ~/.config/reel-summarize/config.toml";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [(pkgs.callPackage ../../pkgs/reel-summarize {})];
    home.file.".config/reel-summarize/config.toml".text = let
      s = cfg.settings;
    in ''
      host = "${s.host}"
      vision_model = "${s.visionModel}"
      summarize_model = "${s.summarizeModel}"
      whisper_model = "${s.whisperModel}"
      frames_per_second = ${toString s.framesPerSecond}
      max_frames = ${toString s.maxFrames}
    '';
  };
}
