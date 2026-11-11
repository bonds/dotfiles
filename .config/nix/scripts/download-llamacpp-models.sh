#!/usr/bin/env bash
set -euo pipefail
# Download GGUF models for llama.cpp on accismus
# Run this AFTER rebuilding with `nr`
MODEL_DIR="$HOME/.cache/llama.cpp/models"
mkdir -p "$MODEL_DIR"

echo "==> Downloading Qwen2.5-7B-Instruct-Q4_K_M.gguf (4.7 GB)..."
curl -fL -o "$MODEL_DIR/Qwen2.5-7B-Instruct-Q4_K_M.gguf" \
  "https://huggingface.co/bartowski/Qwen_Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf" \
  --retry 3 --retry-delay 10 --progress-bar

echo "==> Starting llama.cpp server..."
launchctl bootstrap gui/501 "$HOME/Library/LaunchAgents/org.nixos.llamacpp-serve.plist" 2>/dev/null || \
  launchctl kickstart -k gui/501/org.nixos.llamacpp-serve 2>/dev/null || true

echo "✓ Done! Test with: curl http://localhost:8080/v1/chat/completions -d '{\"model\":\"qwen2.5:7b\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}'"
