# Osaurus `shell_run` dies when `/workspace` cannot be snapshotted

## Symptom

Inside an Osaurus sandbox, every `shell_run` was refused:

```
can't snapshot /workspace/shared is too large to snapshot
```

`file_read`, `file_write` and `file_search` still worked, so the sandbox looked
healthy — but the agent could not run a single command, and fell back to asking
the user to paste file contents into the chat. The failure reads like a
permissions or provisioning problem, which is misleading.

## Cause

`shell_run` snapshots the mounted workspace before it executes, and refuses
when the workspace is too large. `/workspace` is the host directory
`~/.osaurus/container/workspace/`, mounted by VirtioFS — so its size includes
everything that accumulated there, not just what the current task needs.

Here it was 7.8 GB, almost all leftovers from building the Osaurus source
inside the sandbox:

```
5.8G  build/     arm64-apple-macosx, build.db, checkouts  (derived data)
912M  mc/        *.swiftmodule caches
326M  vendor/    SentryLocal, SparkleLocal dependency checkouts
107M  osaurus/   source checkout (only build-time path edits)
720M  Sentry-*.zip, sparkle.zip
```

There is no size setting to raise: `~/.osaurus/config/sandbox.json` covers
cpus/memory/network, and `tools.json` only carries `browser_snapshot` policy.
The ceiling is a fixed internal limit somewhere below 8 GB.

The guest sees `/workspace/agents/<agent-id>/` (its own home) and
`/workspace/shared`; the host's `$HOME` is not visible at all.

## Fix

Treat `/workspace` as a durable shared folder, not scratch space. After any
sandboxed build, delete the derived artifacts — `build/`, module caches,
dependency checkouts — because they are regenerable and they are what pushes
the workspace past the limit.

Symptom to recognise: tools that touch files work while `shell_run` fails with
a message about snapshotting. Check `du -sh ~/.osaurus/container/workspace`
first, not the sandbox configuration.

Related, and the reason this matters for the memory store: a sandboxed agent
must be given a *small* root. Anything mounted at `/workspace` — a raw
transcript archive, a build tree — eventually breaks command execution for
every agent using that sandbox. When an agent needs a host directory, or a
directory that grows without bound, use **Working Folder** mode with the
sandbox off: it writes through to real host files and does not snapshot.

Verified 2026-10-25 — working-folder write-through, sandbox read isolation, and
this snapshot ceiling, all on accismus.
