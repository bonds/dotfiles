# Wiring the `pi` coding agent (earendil-works/pi) into accismus

**Date:** 2026-10-11 · **Host:** accismus (aarch64-darwin) · **Flake:** /Users/scott/.config/nix
**Status:** changes written, build + all repo checks GREEN, binary verified.
**NOT COMMITTED / NOT PUSHED** — see "Blocker" at the end.

## 1. Files changed

| File | Lines | Change |
|---|---|---|
| `flake.nix` | 51–59 (new), 86 total | new `pi` flake input + `nixpkgs` follows |
| `modules/packages/macos.nix` | 29 (new), 68 total | `inputs.pi…default` in `environment.systemPackages` |
| `flake.lock` | +2 nodes (`pi`, `nixpkgs-darwin-x64`) | locked to pi `cdaf6c2` |

`alejandra` clean on both edited `.nix` files.

### Exact input entry added (`flake.nix:51–59`)

```nix
    # Pi coding agent (earendil-works/pi) — CLI AI coding agent for accismus.
    # Rev-pinned like hermes-agent: it is a from-source npm build with no
    # binary cache, so an unpinned URL would make every `nr --update` chase
    # main and risk a broken source build. Bump the rev deliberately.
    # FOLLOWS nixpkgs-unstable on purpose (upstream targets nixos-unstable):
    # unstable→unstable follows is safe — the AGENTS.md gotcha is about
    # following TO a stable channel — and it dedupes flake.lock.
    pi.url = "git+https://github.com/earendil-works/pi?rev=cdaf6c227d4718a72b59ccd02152c9614df44cfc";
    pi.inputs.nixpkgs.follows = "nixpkgs-unstable";
```

### Exact package entry added (`modules/packages/macos.nix:29`)

```nix
    inputs.pi.packages.${pkgs.stdenv.hostPlatform.system}.default # Pi coding agent (earendil-works/pi, flake input, CLI)
```

Inserted between the `neocode` and `polyptych` lines to keep the `inputs.*`
block alphabetical. accismus only — `sophrosyne` and `metanoia` untouched
(they declare no other AI harness; `modules/packages/macos.nix` is the
accismus-only package list).

## 2. Why this pattern (mirrors existing wiring, nothing invented)

- **Consumption = the `neocode` pattern** (`flake.nix:47–50` +
  `modules/packages/macos.nix:28`): a flake input consumed directly as
  `inputs.<name>.packages.${pkgs.stdenv.hostPlatform.system}.default` in
  `environment.systemPackages`. pi exposes exactly `packages.<system>.pi`
  and `.default`, so no overlay is needed (an overlay would be the
  `hermes-agent` pattern, only justified when a module is involved).
- **Pinning = the `hermes-agent` pattern** (`flake.nix:64`): rev-pinned
  `git+https://…?rev=…`. hermes-agent is the repo's precedent for a
  third-party repo that is a heavy from-source build; pi is the same
  (npm monorepo, no binary cache), so an unpinned URL would make every
  `nr --update` re-resolve `main` and risk a broken source build.
- **`nixpkgs` follows = `nixpkgs-unstable`** (hermes-agent, `flake.nix:65`).
  Upstream's flake targets `github:NixOS/nixpkgs/nixos-unstable`. The
  AGENTS.md gotcha is about following *to a stable channel* — an
  unstable→unstable follows is the documented-safe case, and it avoids a
  second `nixpkgs` node in `flake.lock`.
- **`nr-pins` / `flake-pins.json`: no entry needed.** The tooling's safety
  rule (enforced in code) is `owner == NixOS && repo == nixpkgs` — it only
  ever pins nixpkgs inputs, so a third-party input is out of scope by design.
- `pi/nixpkgs-darwin-x64` (upstream's Intel-macOS branch, unused on
  aarch64) is deliberately left un-followed; it is only an extra lock node.

## 3. Lock update (only the new input was touched)

```
$ XDG_CACHE_HOME=/tmp/nixcache nix flake update pi
• Added input 'pi':
    'git+https://github.com/earendil-works/pi?ref=refs/heads/main&rev=cdaf6c227d4718a72b59ccd02152c9614df44cfc' (2026-10-11)
• Added input 'pi/nixpkgs':
    follows 'nixpkgs-unstable'
• Added input 'pi/nixpkgs-darwin-x64':
    'github:NixOS/nixpkgs/c19db427a1fdfc7591c0b0baeb4665dcef2c61da' (2026-09-02)
```

Verified in `flake.lock` after the update:

| node | rev | note |
|---|---|---|
| `pi` | `cdaf6c227d4718a72b59ccd02152c9614df44cfc` | new |
| `nixpkgs-darwin-x64` | `c19db427a1fdfc7591c0b0baeb4665dcef2c61da` | new (pi's x64 input) |
| `nixpkgs` | `774debe7a0d1b496e35677ad955a1011c6ff74f3` | **UNCHANGED** (pin intact) |
| `nixpkgs-unstable` | `c9fe7d12cd78d1adcd12dd15e24432dde5b155a0` | **UNCHANGED** (pin intact) |

Node-name diff: only `pi` and `nixpkgs-darwin-x64` added. No unrelated input bumped.

## 4. Build (non-activating) — PASSED

```
$ cd ~/.config/nix && nh darwin build .#accismus
[A+] pi                              1.1.0, +120 MiB
[A.] pi-workspace-packages           1.1.0, +8.89 MiB
…
PATHS: 1410 -> 1530 (+124, -4)
SIZE: 18.4 GiB -> 18.7 GiB
DIFF: +231 MiB
```
exit code 0. `nix flake check --no-build` and `nix build
.#checks.aarch64-darwin.secrets-check` (gitleaks: "no leaks found") also pass,
as do `alejandra --check`, `deadnix` and `statix check .`.

No activation was performed:

```
$ readlink -f /nix/var/nix/profiles/system
/nix/store/63a60s4hrl4rz72gz4jkivbxshp9arax-darwin-system-26.05.c3e90c8   # unchanged
$ ls /run/current-system/sw/bin/pi
ls: cannot access '/run/current-system/sw/bin/pi': No such file or directory
```

### Binary evidence (from the built system out-path)

```
$ nix build .#darwinConfigurations.accismus.config.system.build.toplevel --no-link --print-out-paths
/nix/store/6cv8dxn8jyr2vhazarcg84a4idj1vq1d-darwin-system-26.05.c3e90c8

$ ls -l $OUT/sw/bin/pi
… /nix/store/w508k0q5fkmcl5xm40x8mqd7wcpfhzv6-pi-1.1.0/bin/pi

$ $OUT/sw/bin/pi --version
1.1.0

$ $OUT/sw/bin/pi --help
pi - AI coding assistant with read, bash, edit, write tools
Usage:
  pi [options] [--] [@files...] [messages...]
…
```

(The `Warning: Invalid settings file /Users/scott/.pi/agent/settings.json:
EPERM` line on `--help` is the agent sandbox refusing a write to `~/.pi`;
expected here, not a packaging problem.)

## 5. Blocker — commit + push could not be performed

The agent shell is sandboxed to the working folder plus `/tmp`
(`touch ~/.config/dotfiles/x` → `Operation not permitted`). The dotfiles repo
is a **bare repo at `~/.config/dotfiles` with worktree `$HOME`** (AGENTS.md),
i.e. outside that boundary, so `git add`/`commit` fails on `index.lock`:

```
fatal: Unable to create '/Users/scott/.config/dotfiles/index.lock': Operation not permitted
```

`/Users/scott/.config/nix` is **not** itself a git repository (no `.git`), so
there is no in-boundary repo to commit to. Nothing was committed or pushed.

### Ready-to-run handover (run from `~`)

```bash
cd ~
export XDG_CACHE_HOME=/tmp/nixcache   # the sandbox also blocks ~/.cache/nix
git --git-dir=$HOME/.config/dotfiles --work-tree=$HOME add \
  .config/nix/flake.nix .config/nix/flake.lock .config/nix/modules/packages/macos.nix
git --git-dir=$HOME/.config/dotfiles --work-tree=$HOME commit -m \
"pi: wire the earendil-works/pi coding agent into accismus

Adds the pi CLI coding agent (github.com/earendil-works/pi) as a flake
input and puts it on PATH for accismus only, mirroring how neocode is
consumed (inputs.<name>.packages.<system>.default in
modules/packages/macos.nix).

- rev-pinned like hermes-agent: pi is a from-source npm build with no
  binary cache, so an unpinned URL would make every \`nr --update\` chase
  main and risk a broken source build.
- inputs.nixpkgs follows nixpkgs-unstable (upstream targets
  nixos-unstable); unstable->unstable follows is the documented-safe case
  and it dedupes flake.lock (no extra nixpkgs node).
- only pi and pi/nixpkgs-darwin-x64 were added to flake.lock; the
  nixpkgs / nixpkgs-unstable pins are untouched.
- nr-pins needs no entry: it only manages NixOS/nixpkgs inputs."
git --git-dir=$HOME/.config/dotfiles --work-tree=$HOME push origin main
git --git-dir=$HOME/.config/dotfiles --work-tree=$HOME push sophrosyne main
```

## 6. What Scott still runs himself

```
nr          # activates; `pi` then lands at /run/current-system/sw/bin/pi
```

Nothing else is required — the build is green, so `nr` will be a fast
substitute-and-switch.

## 7. Left untouched

- `pi-harness-declaration-report.md` (the earlier read-only investigation,
  untracked; hidden from `git status` because the bare repo sets
  `status.showUntrackedFiles = no`). Not part of this change.
- `result` (stale symlink from an earlier unrelated build; gitignored).
