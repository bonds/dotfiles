# Is the "pi" coding agent (github.com/earendil-works/pi) declared or installed via Scott's Nix config?

**Date:** 2026-10-10 · **Host:** accismus (read-only investigation) · **Flake:** /Users/scott/.config/nix

## Verdict: NO — not declared, not installed, not referenced anywhere.

The earendil-works/pi coding agent is **absent** from Scott's flake: no flake input, no
package attribute, no overlay, no `home.packages` / `environment.systemPackages` entry,
no `pi` binary on PATH.

## Evidence

### 1. Standalone `pi` token — zero hits (whole repo, all file types, .git excluded)
```
$ grep -rnwI --exclude-dir=.git 'pi' .
(no output)
```

### 2. `earendil` — zero hits (whole repo incl. flake.lock, flake-pins.json)
```
$ grep -rniI 'earendil' . 2>/dev/null | grep -v '^\./\.git/'
(no output)
```

### 3. flake.nix inputs (lines 3–72) — no pi/earendil input
Declared inputs: `nixpkgs`, `nixpkgs-unstable`, `nix-darwin`, `home-manager`,
`nix-index-database`, `vudials`, `polyptych`, `neocode`, `flake-parts`, `agenix`,
`hermes-agent`. No `earendil-works/pi` (or any pi flake).

### 4. flake.lock nodes — no pi/earendil node
Node names: `agenix, flake-parts, hermes-agent, home-manager, home-manager_2, neocode,
nix-darwin, nix-index-database, nixpkgs, nixpkgs-lib, nixpkgs-unstable` (+ transitive).
```
$ grep -niI -E '(earendil|\bpi\b)' flake.lock
(no output)
```

### 5. flake-pins.json — only nixpkgs / nixpkgs-unstable pins (thrift, anyio). No pi.

### 6. PATH check — no `pi` binary
```
$ command -v pi ; which -a pi
pi not found   (rc=1)
```

## The only `harness`/`pi` grep hits are INCIDENTAL (not the pi agent)
| file:line | literal | why unrelated |
|---|---|---|
| `nr-pins-tests.sh:2` | `# nr-pins test harness` | test harness script |
| `AGENTS.md:384` | `a harness that launches Zen repeatedly` | doc prose |
| `modules/home/macos-apps.nix:50` | `osaurus # native macOS AI agent harness` | Osaurus app |
| `modules/overlays/osaurus/default.nix:29` | `description = "Own your AI — native macOS AI agent harness"` | Osaurus app |
| `modules/overlays/lix/default.nix:17` | `inside the harness still catches...` | comment about Lix |

No standalone `pi` token appears in any of these.

## AI coding-harness tools that ARE declared (so Scott can confirm which he meant)
All of the following are on **accismus only**; sophrosyne and metanoia declare none of them.

| Tool | Where declared | What it is |
|---|---|---|
| `opencode` | `modules/packages/macos.nix:38`; overlay `modules/overlays/opencode/default.nix:20` | AI coding agent CLI (anomalyco/opencode v1.18.35, binary overlay) |
| `opencode-desktop` | `modules/packages/macos.nix:39`; overlay `.../opencode/default.nix:48` | OpenCode Electron desktop app |
| NeoCode | `modules/packages/macos.nix:28` (`inputs.neocode...default`) | native macOS SwiftUI client for OpenCode |
| `raven` | `modules/packages/macos.nix:50` (`pkgs/raven`) | "AI-native CLI agent (EverMind-AI Raven)" |
| hermes-agent | `flake.nix:64`; `hosts/accismus/configuration.nix:259–260` (`programs.hermes-agent.enable`/`.desktop.enable`) | Nous Research Hermes Agent (+ desktop) |
| osaurus | `modules/home/macos-apps.nix:50` | native macOS AI agent harness |
| openfang | overlay `modules/overlays/openfang` | desktop app (openfang-desktop) |
| oxillama | `modules/packages/macos.nix:47` | pure-Rust LLM inference engine |
| openspec | `modules/packages/macos.nix:46` | Fission-AI spec-driven dev CLI |

## Per-host applicability
- **accismus:** all of the above AI harnesses (darwin-only overlays + hermes home-manager module).
- **sophrosyne:** none.
- **metanoia:** none.
- **pi (earendil-works/pi):** none, on any host.

## Conclusion
If Scott wants the `pi` coding agent, it is **not yet wired in** — it would need a new
flake input (`earendil-works/pi`, exposing `packages.<system>.pi`, `apps.<system>.pi`,
`overlays.default`) added to `flake.nix` and the package added to `home.packages` or
`environment.systemPackages`. Nothing currently does that.
