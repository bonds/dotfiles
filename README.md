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

`what-changed` diffs two nix system closures, finds which packages changed, fetches their changelogs, and summarizes each using a local LLM (via ollama).

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
- **LLM summarization** — uses `qwen2.5:1.5b` via ollama (configurable: OpenAI-compatible APIs also supported)
- **Caching** — metadata, changelogs, and LLM summaries are cached so repeat runs are instant
- **Output formats** — rich terminal output, `--json`, `--brief`
- **Config file** — `~/.config/what-changed/config.toml`
- **Test suite** — 145+ tests, run via `nix flake check`

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
    model = "qwen2.5:1.5b";
    timeout = 180;
  };
}
```

### Requirements

- [ollama](https://ollama.com) running locally with the default model pulled (`ollama pull qwen2.5:1.5b`)
- Nix (obviously)
- Python 3.10+ (included via nix package)

### Configuration

```toml
# ~/.config/what-changed/config.toml
model = "qwen2.5:1.5b"
timeout = 180
prompt_style = "strict"    # default, strict, concise, no-hallucinate, numbered
backend = "ollama"         # or "openai" for OpenAI-compatible APIs
host = "http://localhost:11434"
max_bullets = 5
```

## License

MIT
