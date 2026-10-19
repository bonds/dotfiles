# Piping a command to `tail` reports success, and hides the failure from capture

**Date:** 2026-10-19

## Symptom

A `git push` that never landed reported a clean exit:

```
$ timeout 45 git --git-dir=… push origin main 2>&1 | tail -6
exit: 0
```

`origin/main` had not moved. The same thing happened again later: a push failed
with `Connection closed by … port 22`, the tool call reported success, and the
failure was only noticed by comparing `rev-parse` against the remote.

## Cause

A pipeline's exit status is the **last** command's, not the first. `git push … |
tail -6` exits with `tail`'s status, which is 0 whenever `tail` succeeds — and
`tail` always succeeds. Same for `| sed …`, `| rg …`, `| head`.

Two consequences, the second worse than the first:

1. A failure is invisible unless you look at the actual state.
2. `learnings-capture.ts` keys on tool failure, so a masked failure never reaches
   `~/.pi/agent/inbox.md`. The capture loop silently drops exactly the failures
   that were easy to miss.

## Fix

Never end a state-changing command in a pipe. If output must be trimmed, keep the
real status:

```bash
# bash
set -o pipefail
git push origin main 2>&1 | tail -5
echo "${PIPESTATUS[0]}"
```

```fish
# fish
git push origin main 2>&1 | tail -5
echo $pipestatus[1]
```

Better, verify the outcome rather than the exit code:

```fish
set -l G git --git-dir=$HOME/.local/share/dotfiles --work-tree=$HOME
$G push origin main; and echo "origin: $($G rev-parse --short origin/main)"
```

**Lesson:** `| tail` turns any command into one that cannot fail. For pushes,
check `rev-parse` against the remote; for anything else, `pipefail` or
`$pipestatus[1]`.
