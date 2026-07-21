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
            default = "http://localhost:8080";
            description = "LLM API host (http://localhost:8080 = llama.cpp, http://localhost:11434 = ollama)";
          };
          backend = lib.mkOption {
            type = lib.types.enum ["openai" "ollama"];
            default = "openai";
            description = "LLM backend (openai = llama.cpp / OpenAI-compatible API)";
          };
          visionModel = lib.mkOption {
            type = lib.types.str;
            default = "qwen2.5:7b";
            description = "Vision model for per-frame OCR (use 'qwen2.5:7b' for text-only, need multimodal GGUF for actual vision)";
          };
          summarizeModel = lib.mkOption {
            type = lib.types.str;
            default = "qwen2.5:7b";
            description = "Model for final summary";
          };
          whisperModel = lib.mkOption {
            type = lib.types.str;
            default = "whisper-small-Q5_K_M.gguf";
            description = "Whisper GGUF model path (downloaded from HuggingFace handy-computer)";
          };
          framesPerSecond = lib.mkOption {
            type = lib.types.int;
            default = 1;
            description = "Frame sampling rate";
          };
          maxFrames = lib.mkOption {
            type = lib.types.int;
            default = 10;
            description = "Maximum frames to analyze (10 takes ~1-2 min with llava:7b on M2)";
          };
          timeout = lib.mkOption {
            type = lib.types.int;
            default = 300;
            description = "HTTP timeout in seconds for LLM API calls";
          };
        };
      };
      default = {};
      description = "Settings written to ~/.config/reel-summarize/config.toml";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [(pkgs.callPackage ../../pkgs/reel-summarize {})];
    home.file.".config/reel-summarize/config.toml".source = let
      format = pkgs.formats.toml {};
      s = cfg.settings;
    in
      format.generate "config.toml" {
        host = s.host;
        backend = s.backend;
        vision_model = s.visionModel;
        summarize_model = s.summarizeModel;
        whisper_model = s.whisperModel;
        frames_per_second = s.framesPerSecond;
        max_frames = s.maxFrames;
        timeout = s.timeout;
      };
  };
}
