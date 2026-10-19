# `rg -r` is `--replace`, not recursive

**Date:** 2026-10-19

## Symptom

Grepping a module appeared to show a corrupted file — the config attribute name
had been replaced by the letter `n`:

```
$ rg -rn 'reel-summarize' .config/nix/modules/home/reel-summarize.nix
  cfg = config.programs.n;
  options.programs.n = {
    enable = lib.mkEnableOption "n — summarize Instagram Reels and YouTube videos…";
      description = "Settings written to ~/.config/n/config.toml";
```

The file was fine. The same command form printed `"n.md".source = …` for
`DECISIONS.md` in `pi.nix`, which looked like a real bug worth reporting.

## Cause

ripgrep's `-r` is `--replace`, which takes a value. So `-rn` parses as
`--replace n` followed by the pattern — every match in the output is rewritten
to `n`. Recursion is ripgrep's default and needs no flag; `grep -r` muscle memory
is what produces this.

There is no config file or alias involved (`RIPGREP_CONFIG_PATH` unset, `rg`
resolves to the plain nix store binary), so nothing warns you.

## Fix

Use `-n` for line numbers, and never combine `-r` with anything:

```bash
rg -n 'reel-summarize' path/            # correct
rg -rn 'reel-summarize' path/           # ✗ silently rewrites every match to "n"
```

Confirm the flag semantics with a control run before believing a surprising
result:

```bash
rg -n 'pattern' file | head -3    # ground truth
rg -rn 'pattern' file | head -3   # what you actually asked for
```

**Lesson:** when a grep result looks like the file is corrupted, suspect the
grep before the file. Any `-r` on ripgrep is `--replace`; recursive is implicit.
