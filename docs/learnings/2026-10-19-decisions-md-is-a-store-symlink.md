# `~/DECISIONS.md` is a read-only nix store symlink

**Date:** 2026-10-19

## Symptom

An edit to `~/DECISIONS.md` failed with:

```
Could not edit file: /Users/scott/DECISIONS.md. Error code: EACCES.
```

The file looks ordinary in `ls`, but:

```
$ ls -la DECISIONS.md
lrwxr-xr-x  DECISIONS.md -> /nix/store/rb9bkmqp…-home-manager-files/DECISIONS.md
```

## Cause

`modules/home/pi.nix` generates it from the tracked `pkgs/pi/decisions.md`:

```nix
"DECISIONS.md".source = piConfig + "/decisions.md";
```

So `$HOME/DECISIONS.md` is a symlink into the nix store, which is read-only by
design. The editable source is the repo file, and the change only appears in
`$HOME` after a rebuild — which an agent must not run.

The same applies to every other home-manager file: `~/.config/tmux/tmux.conf`,
`~/.config/ghostty/config`, `~/.config/what-changed/config.toml`,
`~/.config/sleepwatcher/*.sh`, `~/.config/halloy/config.toml`, and so on. A
directory listing shows them as ordinary files inside the directory; only the
symlink target reveals they are store paths.

## Fix

Edit the repo path, then hand the rebuild to Scott:

```bash
# edit this, not $HOME
~/.config/nix/pkgs/pi/decisions.md

# after changing AGENTS.md / a skill description / DECISIONS.md, run the evals
~/.config/nix/pkgs/pi/evals/run.sh      # expect "N/N passed"

# then Scott runs `nr`
```

Check ownership before editing anything under `$HOME` that looks config-shaped:

```bash
readlink -f ~/DECISIONS.md     # /nix/store/... ⇒ generated, not editable
```

**Related trap:** the `learning` tool cannot write from `$HOME` — it reports
*"`/Users/scott` is not inside a git repository"* — because git's upward search
cannot find a bare repo that is only reachable via `--git-dir`. Write
`docs/learnings/` entries directly instead.

**Lesson:** in a nix-managed home, "the file is right there" says nothing about
whether it is editable. `readlink -f` first; `EACCES` means you are editing the
store, not a config.

## Evidence

`session://pi/01a1525b-e95e-71f0-9f75-d46b9e77428d#turn-380`

Found by searching the archive for a verbatim phrase from this entry (2 hit(s) for `Could not edit file: /Users/scott/DECISIONS.md. Error code: `), within 3 days of the entry date.

> - Entry 3: EACCES message exact? "Could not edit file: /Users/scott/DECISIONS.md. Error code: EACCES." ✓ from the tool output.
