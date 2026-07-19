{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.llamacpp-server;
in {
  options.services.llamacpp-server = {
    enable = lib.mkEnableOption "llama-server (llama.cpp) LLM inference server";
    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host address to bind to";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port to listen on";
    };
    model = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to GGUF model file (auto-downloaded on first start if missing)";
    };
    modelUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "URL to download the model GGUF from when it doesn't exist on disk";
    };
    mmproj = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to multimodal projector GGUF for vision models";
    };
    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra arguments to pass to llama-server";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llama-cpp;
      description = "llama.cpp package to use";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.llamacpp-server =
      {
        description = "llama-server (llama.cpp)";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];
        serviceConfig = {
          ExecStart = lib.concatStringsSep " " (
            [
              "${cfg.package}/bin/llama-server"
              "--host"
              cfg.host
              "--port"
              (toString cfg.port)
            ]
            ++ lib.optionals (cfg.model != null) ["-m" cfg.model]
            ++ lib.optionals (cfg.mmproj != null) ["--mmproj" cfg.mmproj]
            ++ cfg.extraArgs
          );
          Restart = "always";
          RestartSec = 5;
        };
      }
      // lib.optionalAttrs (cfg.model != null && cfg.modelUrl != null) {
        # Auto-download model if it doesn't exist on disk
        preStart = lib.mkBefore ''
          if ! [ -f "${cfg.model}" ]; then
            mkdir -p "$(dirname "${cfg.model}")"
            echo "→ downloading model to ${cfg.model}..."
            ${pkgs.curl}/bin/curl -fSL -o "${cfg.model}.tmp" "${cfg.modelUrl}" \
              --retry 3 --retry-delay 5
            mv "${cfg.model}.tmp" "${cfg.model}"
            echo "✓ model downloaded"
          fi
        '';
      };
  };
}
