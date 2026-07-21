{lib, ...}: {
  options.programs.what-changed = {
    enable = lib.mkEnableOption "what-changed — show changelog summaries after nix rebuilds";

    settings = lib.mkOption {
      type = lib.types.submodule {
        options = {
          backend = lib.mkOption {
            type = lib.types.enum ["ollama" "openai"];
            default = "openai";
            description = "LLM backend to use for summarization (openai = llama.cpp / OpenAI-compatible API)";
          };
          host = lib.mkOption {
            type = lib.types.str;
            default = "http://localhost:8080";
            description = "LLM API host (port 8080 = llama.cpp, port 11434 = ollama)";
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
