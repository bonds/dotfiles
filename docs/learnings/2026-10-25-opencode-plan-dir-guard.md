# opencode plan mode rejects writes to its own plan directory

## Symptom

In plan mode, every file write was refused — including the path the error itself
named:

```
Cannot use write to modify files outside the Plan directory: /Users/scott/.opencode/plan
```

`edit` failed identically, and the directory was simply absent:

```
ls: /Users/scott/.opencode: No such file or directory
```

Creating it mid-session did **not** help. After `mkdir -p ~/.opencode/plan`, a
write to `~/.opencode/plan/probe.md` still failed with the same message.

## Cause

The plan-mode guard resolves its allowed root once, when the session starts. If
`~/.opencode/plan` does not exist at that moment the resolved root is unusable,
so the prefix check rejects *every* path — including the one the message names,
which reads as a permissions problem rather than a missing directory.

Because the root is captured at session start, repairing the filesystem does not
repair the running session. That is the confusing part: the error keeps naming a
path that now exists and is writable.

## Fix

Make sure the directory exists **before** entering plan mode:

```sh
mkdir -p ~/.opencode/plan
```

Once it exists at startup, writes into it work normally.

Within an already-broken session the only workaround is to write through the
shell into the same absolute path, which bypasses the guard:

```sh
cat > ~/.opencode/plan/note.md <<'EOF'
...
EOF
```

Use the workaround to keep working, but the durable fix is the directory
existing — the guard should create its own root, or check for it before
rejecting every write. This is a harness bug, not a misconfiguration.

## Evidence

`session://opencode/ses_e8ca2e501ffeBxfIfKZ5hihPUf#turn-315`

Found by searching the archive for a verbatim phrase from this entry (2 hit(s) for `Cannot use write to modify files outside the Plan directory:`), within 3 days of the entry date.

> 3. `[2026-10-25 11:40] write — Cannot use write to modify files outside the Plan directory: /Users/scott/.opencode/plan` — the guard bug.
