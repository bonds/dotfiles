# Secretive/TouchID failures don't only look like `Permission denied (publickey)`

**Date:** 2026-10-19

## Symptom

Two `git push` attempts failed in one session with **different** errors:

```
# to GitHub
git@github.com: Permission denied (publickey).
fatal: Could not read from remote repository.

# to sophrosyne
Connection closed by 108.205.203.213 port 22
fatal: Could not read from remote repository.
```

The second reads like a network blip, so it was retried as one. The retry succeeded
— because Scott had come back to the machine and approved the TouchID prompt. He
had been AFK for the first attempt.

Throughout, the agent looked healthy:

```
$ ssh-add -l
256 SHA256:U487fmd… scott's-super-secure-thing@secretive… (ECDSA)
```

## Cause

Secretive signs only after a TouchID approval, and the identity stays listed in
the agent whether or not signing will be approved. With nobody at the machine no
approval arrives, and the SSH handshake dies — *where* it dies varies, so the
message does too: a publickey denial if it fails at authentication, or a
peer-closed connection if the server drops the stalled handshake.

**The two messages are the same condition.** Neither is evidence of a broken
remote, and `ssh-add -l` listing the key is not evidence that signing works.

## Fix

Treat both as the TouchID hand-off. Check the state with `rev-parse`, not with the
exit code:

```fish
set -l G git --git-dir=$HOME/.local/share/dotfiles --work-tree=$HOME
$G push origin main
echo "local: $($G rev-parse --short main)  origin: $($G rev-parse --short origin/main)"
```

If the remote has not moved, ask Scott to push when he is at the keyboard. Do not
retry in a loop: a retry only "works" if the approval prompt happens to be
answered, which is luck, not diagnosis.

**Lesson:** a `Connection closed by … port 22` on a push to a Secretive-backed
host is a TouchID timeout, not a network fault. Both signatures mean "hand off".

## Evidence

`session://pi/01a1525b-e95e-71f0-9f75-d46b9e77428d#turn-445`

Found by searching the archive for a verbatim phrase from this entry (20 hit(s) for `git@github.com: Permission denied (publickey).`), within 3 days of the entry date.

> - `git@github.com: Permission denied (publickey).` ✓ exact
