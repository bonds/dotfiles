# photos-backup failure logging — result

## Status: the in-place edit could NOT be made by this agent

`$HOME/bin/photos-backup` is **unchanged**. The agent sandbox denies every write
under `$HOME` except `/Users/scott/.config/nix`, regardless of mechanism:

```
$ printf 'x\n' >> "$HOME/bin/photos-backup"
zsh:1: operation not permitted: bin/photos-backup
$ touch "$HOME/agent-write-test"
touch: cannot touch '/Users/scott/agent-write-test': Operation not permitted
$ cd "$HOME" && patch -p1 < photos-backup-failure-logging.patch
patching file 'bin/photos-backup'
Can't create '/var/folders/.../patchoWoNIHmykBg', output is in '...'
$ git --git-dir=$HOME/.local/share/dotfiles --work-tree=$HOME status --short -- bin/photos-backup
(empty)
```

So the finished script was written into the working folder instead. Two
deliverables, both verified:

- **`photos-backup.new`** — the complete final script (114 lines). Byte-identical
  content to what `$HOME/bin/photos-backup` should be. Scott can install it with
  `install -m 755 ~/.config/nix/photos-backup.new ~/bin/photos-backup`.
- **`photos-backup-fixed.patch`** — same change as a unified diff, applies with
  `patch -p1 -d "$HOME" < ~/.config/nix/photos-backup-fixed.patch`
  (dry-run verified: `patching file 'bin/photos-backup'`).

**These files are not durable** — they are untracked files in the `$HOME/.config/nix`
checkout. The change must be mirrored as a commit touching `bin/photos-backup`
in the dotfiles repo, or the next `config checkout main -- .` will revert them.

## Two corrections to the task's assumptions

1. **The git dir is `$HOME/.local/share/dotfiles/bare`**, not
   `$HOME/.local/share/dotfiles` (`fatal: not a git repository`). Use
   `--git-dir=$HOME/.local/share/dotfiles/bare --work-tree=$HOME`.
2. The untracked `photos-backup-failure-logging.patch` was reused as-is for
   change (1) — but it does **not** cover change (2); the two `exit 0` guard
   paths were hand-written here.

## What changed

1. **Failure logging on the launch.** `open -j -W "$APP"` now runs as
   `open -j -W "$APP" 2>>"$ERRFILE" >>"$LOGFILE" || OPEN_RC=$?` under
   `set -euo pipefail`. The patch goes further and judges the run from
   photo-export's own `/tmp/photo-export.log` (since `open -W` never propagates
   the app's exit status), copying the run's new tail to
   `~/Library/Logs/photos-backup.run.log`. Success now requires
   `photo-export: SUMMARY exported=<n> skipped=<n> failed=<n>`.
2. **Both broken-install guards now `exit 1`** with the word `FAILED` in the log
   (app missing; `config.toml` missing `remoteHost`).
3. **Unchanged:** `LOGFILE`/`ERRFILE` paths, lock/`acquire_lock`/`trap` logic, the
   `set -euo pipefail` header, and the `backup already running, skipping` path
   (still `exit 0` — a legitimate no-op).

## Exact new log line strings (all appended to ~/Library/Logs/photos-backup.out.log)

```
$(date) — backup FAILED (exit 1): photo-export.app missing at $APP; nothing to run
$(date) — backup FAILED (exit 1): config.toml missing remoteHost (SFTP not configured); refusing to run
$(date) — backup FAILED (exit $OPEN_RC): open could not launch or finish $APP; see $ERRFILE
$(date) — backup FAILED (exit 1): photo-export exited before SUMMARY${FATAL:+ — $FATAL}; see $RUNCOPY
$(date) — backup FAILED (exit 1): $SUMMARY; see $RUNCOPY
$(date) — backup complete (SUMMARY exported=<n> skipped=<n> failed=<n>)
```

(`—` is U+2014 em dash, matching the existing lines. The success line format
changed from `— backup complete` to `— backup complete (exported=… skipped=…
failed=…)`.)

### Grep for failures

```sh
grep -E 'backup FAILED|backup ERROR' "$HOME/Library/Logs/photos-backup.out.log"
```

### Tail 25 lines of the final script (`photos-backup.new`)

```
START=$(wc -c < "$RUNLOG" 2>/dev/null || echo 0)
OPEN_RC=0
open -j -W "$APP" 2>>"$ERRFILE" >>"$LOGFILE" || OPEN_RC=$?

RUN_OUT=$(tail -c "+$((START + 1))" "$RUNLOG" 2>/dev/null || true)
printf '%s\n' "$RUN_OUT" > "$RUNCOPY"
SUMMARY=$(printf '%s\n' "$RUN_OUT" | grep -m1 '^photo-export: SUMMARY exported=' || true)
FATAL=$(printf '%s\n' "$RUN_OUT" | grep -m1 'FATAL' || true)

if [ "$OPEN_RC" -ne 0 ]; then
  echo "$(date) — backup FAILED (exit $OPEN_RC): open could not launch or finish $APP; see $ERRFILE" >> "$LOGFILE"
  exit "$OPEN_RC"
fi

if [ -z "$SUMMARY" ]; then
  echo "$(date) — backup FAILED (exit 1): photo-export exited before SUMMARY${FATAL:+ — $FATAL}; see $RUNCOPY" >> "$LOGFILE"
  exit 1
fi

if printf '%s' "$SUMMARY" | grep -qE 'failed=[1-9]'; then
  echo "$(date) — backup FAILED (exit 1): $SUMMARY; see $RUNCOPY" >> "$LOGFILE"
  exit 1
fi

echo "$(date) — backup complete (${SUMMARY#photo-export: })" >> "$LOGFILE"
```

## Verification run

```
$ bash -n photos-backup.new
bash-n: OK                                  # rc=0

$ /nix/store/l5g1wgv104p4fx9zaxygxmcly7b68f4b-shellcheck-0.11.0-bin/bin/shellcheck photos-backup.new
ShellCheck version: 0.11.0
(silent) rc=0                               # no warnings at all
# `shellcheck` is not on PATH; `nix run nixpkgs#shellcheck` fails with a
# read-only eval-cache DB in this sandbox, so the store copy was used directly.

$ cd "$HOME" && patch -p1 --dry-run < "$HOME/.config/nix/photos-backup-fixed.patch"
patching file 'bin/photos-backup'            # rc=0
```

Backup itself was NOT run. No `nr`/`darwin-rebuild`/`nixos-rebuild`. Nothing committed or pushed.

## `git status --short` (dotfiles bare git-dir, work-tree $HOME, run from ~/.config/nix)

```
 M hosts/accismus/configuration.nix
 M hosts/sophrosyne/configuration.nix
 M hosts/sophrosyne/security.nix
 M hosts/sophrosyne/services.nix
 M pkgs/photokit-export/photo-export.swift
```

`bin/photos-backup` does **not** appear — it is still the unmodified tracked
version. Note the sophrosyne files are also dirty; they were not touched here.
(Untracked files such as `photos-backup.new` and `photos-backup-fixed.patch` are
hidden by `status.showUntrackedFiles=no`.)
