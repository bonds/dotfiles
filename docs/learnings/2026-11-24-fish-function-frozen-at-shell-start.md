# A fish function is snapshotted at shell start, so an edited `nr` keeps running the old one

**Symptom.** Three days after `oxillama` was dropped in dd681cf, `nr --update`
still printed

```
bash: pkgs/oxillama/update.sh: No such file or directory
```

and then carried on with the rest of the update. The file on disk is correct:
`rg oxillama ~/.config/fish/conf.d/15-functions.fish` finds nothing, `$HOME`
is at `main`, and `$HOME/.config/nix/pkgs/oxillama` is gone.

**Cause.** `conf.d/*.fish` is sourced once, when the shell starts; the function
body then lives in that shell's memory. `nr` applies `main` into `$HOME` but
cannot reach into a shell that is already running, so a terminal opened before
the commit keeps executing the pre-commit `nr`. The stale body ran
`bash pkgs/oxillama/update.sh` from `$HOME/.config/nix` — where the directory no
longer exists — and `bash` reports a missing script without failing the caller,
so the update continued and looked half-broken rather than obviously stale.
Evidence is cheap: `ps -Ao pid,lstart,command | grep fish` showed shells from
Nov 11 and Nov 14, both older than the Nov 21 commit.

**Fix.** `exec fish` (or a new terminal / tmux session) after any change to
`conf.d/`, then re-run. When a `nr` error names a file that `rg` cannot find in
the repo, check the shell's age before editing anything — the message may
describe a version of the function that no longer exists on disk. Running
shells: `ps -Ao pid,lstart,command | grep fish`.
