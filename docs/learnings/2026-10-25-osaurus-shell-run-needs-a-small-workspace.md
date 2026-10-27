# Osaurus sandbox change tracking gives up above 2 GiB or 25 000 entries

## Symptom

Inside an Osaurus sandbox, `shell_run` would not run. `file_read`, `file_write`
and `file_search` all worked, so the sandbox looked healthy while no command
could execute. The agent explained it as:

```
can't snapshot /workspace/shared is too large to snapshot
```

That string **appears nowhere in the source**. It was the model paraphrasing an
error, and it sent the investigation at the wrong mechanism for a while. Treat
any error a model quotes as a paraphrase until it matches a literal.

## Cause

Two budgets live in
`Packages/OsaurusCore/Services/Sandbox/SandboxWorkspaceChangeTracker.swift`
(Osaurus 0.25.25):

```swift
private static let maxTrackedEntries = 25_000          // entries
static let maxBaselineBytes: Int64 = 2 * 1024 * 1024 * 1024   // 2 GiB
```

`maxBaselineBytes` counts **tracked file content**: directories and symlinks
count as zero, so it is the sum of file sizes in the tree.

Crossing either budget does *not* fail the call. `withinBudget` logs and returns
nil, `beginCheckpoint` returns a token with no pre-manifests, and the tool runs
anyway — the only loss is the Changes/undo record:

```swift
guard bytes <= Self.maxBaselineBytes else {
    Self.log.warning("skipping change tracking for …: … tracked bytes exceed the baseline budget")
    return nil
}
```

So the size gate cannot deny a command by itself. What the size really costs is
the **scan**: `beginCheckpoint` walks the entire tree to build a manifest before
every mutation-capable call, and `shell_run` is one of them
(`mutatesSandboxWorkspace = true`). On an 8.9 GB build tree that walk is the
plausible reason the call never completed — the code comment on
`maxTrackedEntries` is explicit that the entry limit exists to avoid "stalling
every tool call on a giant scan".

Unconfirmed: whether the original denial was that walk timing out, an approval
gate, or the model declining for its own reasons. The measured facts are below;
the mechanism is inference.

## Fix

Keep `/workspace` (host: `~/.osaurus/container/workspace/`, mounted by
VirtioFS) **under 2 GiB of file content and 25 000 entries**. It is a durable
shared folder, not scratch: after any sandboxed build, delete the derived
artifacts — `build/`, `*.swiftmodule` caches, dependency checkouts — because
they are regenerable and they are what pushes the tree over both budgets.

Measured on accismus 2026-10-25: 8.9 GB → `shell_run` did not work; 1.1 GB →
it did (exit 0). Clearing a `build/` tree of 5.8 GB, 912 MB of module caches and
326 MB of vendored checkouts was the fix.

Related, and the reason this matters for the memory store: a sandboxed agent
must be given a small root. Anything that grows without bound — a raw transcript
archive, a build tree — eventually stops command execution for every agent
sharing that sandbox, or at minimum silently disables undo. When an agent needs
a host directory or an unbounded one, use **Working Folder** mode with the
sandbox off: it writes through to real host files and snapshots nothing.

## Evidence

`session://opencode/ses_e8ca2e501ffeBxfIfKZ5hihPUf#turn-168`

Found by searching the archive for a verbatim phrase from this entry (7 hit(s) for `can't snapshot /workspace/shared is too large to snapshot`), within 3 days of the entry date.

> 2. **CRITICAL NEW INFO**: `shell_run` is **denied** with "**can't snapshot /workspace/shared is too large to snapshot**".
