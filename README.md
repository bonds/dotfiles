# bonds/dotfiles

Personal dotfiles and Nix flake for macOS (nix-darwin) and NixOS machines.

## What's here

- **Nix flake** (`~/.config/nix/`) — manages three machines: accismus (macOS), sophrosyne (NixOS server), metanoia (NixOS workstation)
- **Shell config** — fish + starship + atuin across all machines
- **Editor config** — Helix editor settings
- **SSH config** — Secretive-agent-based SSH with ControlMaster
- **Scripts** (`bin/`) — cross-platform utilities
- **`what-changed`** — a tool for showing LLM-summarized changelogs after nix rebuilds

## what-changed

`what-changed` diffs two nix system closures, finds which packages changed, fetches their changelogs, and summarizes each using a local LLM (llama.cpp's OpenAI-compatible API by default; ollama is also supported).

Run it manually after a rebuild:

```fish
sudo nixos-rebuild switch          # or: darwin-rebuild switch
what-changed -1                     # compare current vs 1 generation ago
```

Or with explicit store paths:

```fish
what-changed /nix/store/xxx-darwin-system-26.05 /nix/store/yyy-darwin-system-26.11
```

Other usage:

```fish
what-changed -1                      # current vs 1 generation ago
what-changed -1 -50                  # 1 gen ago vs 50 gens ago
what-changed 2026-05-01              # current vs gen after May 1
what-changed 2026-01-01 2025-06-01  # gen after Jan 1 vs gen after Jun 1
what-changed /nix/store/xxx /nix/store/yyy  # explicit store paths
what-changed --benchmark             # test model performance
what-changed --brief                 # compact output, no bullets
what-changed --json                  # machine-readable output
```

### Features

- **Smart changelog discovery** — checks `meta.changelog`, GitHub releases, changelog files, known wiki pages, and GitHub API
- **LLM summarization** — uses `qwen2.5-7b` via a llama.cpp OpenAI-compatible API by default (configurable: `ollama` is also supported)
- **Caching** — metadata, changelogs, and LLM summaries are cached so repeat runs are instant
- **Output formats** — rich terminal output, `--json`, `--brief`
- **Config file** — `~/.config/what-changed/config.toml`
- **Test suite** — 166 tests, run via `nix flake check`

### Installing in your Nix config

Add as a flake input:

```nix
{
  inputs.what-changed.url = "github:bonds/dotfiles?dir=.config/nix/pkgs/nix-what-changed";
}
```

Use the package:

```nix
{ inputs, pkgs, ... }: {
  environment.systemPackages = [ inputs.what-changed.packages.${system}.default ];
}
```

Or use the module (adds the package plus optional config):

```nix
{ inputs, ... }: {
  imports = [ inputs.what-changed.nixosModules.default ];
  programs.what-changed.enable = true;
  programs.what-changed.settings = {
    model = "qwen2.5-7b";
    timeout = 180;
  };
}
```

### Requirements

- A local LLM server. The default config targets a [llama.cpp](https://github.com/ggml-org/llama.cpp) server exposing the OpenAI-compatible API on port 8080 (e.g. `llama-server --port 8080 --model qwen2.5-7b.gguf`). [ollama](https://ollama.com) is also supported: set `backend = "ollama"` and `host = "http://localhost:11434"`.
- Nix (obviously)
- Python 3.10+ (included via nix package)

### Configuration

```toml
# ~/.config/what-changed/config.toml
model = "qwen2.5-7b"
timeout = 180
prompt_style = "curate"    # curate (default), strict, concise, no-hallucinate, numbered
backend = "openai"         # "openai" for llama.cpp / OpenAI-compatible APIs, or "ollama"
host = "http://localhost:8080"
max_bullets = 5
```

## License

CC0 1.0 Universal — see [LICENSE](LICENSE).
