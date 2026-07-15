{lib, ...}: {
  options.programs.what-changed = {
    enable = lib.mkEnableOption "what-changed — show changelog summaries after nix rebuilds";

    settings = lib.mkOption {
      type = lib.types.submodule {
        options = {
          backend = lib.mkOption {
            type = lib.types.enum ["ollama" "openai"];
            default = "ollama";
            description = "LLM backend to use for summarization";
          };
          host = lib.mkOption {
            type = lib.types.str;
            default = "http://localhost:11434";
            description = "LLM API host";
          };
          model = lib.mkOption {
            type = lib.types.str;
            default = "qwen2.5:1.5b";
            description = "LLM model name";
          };
          timeout = lib.mkOption {
            type = lib.types.int;
            default = 40;
            description = "LLM request timeout in seconds";
          };
          maxInputBytes = lib.mkOption {
            type = lib.types.int;
            default = 15000;
            description = "Max changelog bytes sent to LLM";
          };
          maxBullets = lib.mkOption {
            type = lib.types.int;
            default = 5;
            description = "Max bullet points per summary";
          };
          promptStyle = lib.mkOption {
            type = lib.types.str;
            default = "curate";
            description = "Summarization style (curate, strict, default, concise, no-hallucinate, numbered)";
          };
        };
      };
      default = {};
      description = "Settings written to ~/.config/what-changed/config.toml";
    };
  };
}
