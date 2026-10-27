# A live SQLite database reports "database is locked" to readers

## Symptom

Reading a harness database while its harness was running:

```
Error: in prepare, database is locked (5)
```

The connection was opened read-only (`-readonly`, `mode=ro`), the query was a
plain `SELECT`, and the file was not being written by us. Retrying the same
command a moment later sometimes worked and sometimes did not, which reads as a
corrupt or moving file.

## Cause

SQLite takes a lock even for readers, and the `sqlite3` CLI's busy timeout is **0**
by default: when a writer holds a lock, the reader fails immediately instead of
waiting. Live harnesses are constantly writing — `~/.hermes/state.db` gets a row
per tool call, `~/.local/share/opencode/opencode.db` per message part — so the
window is wide.

`mode=ro` does not help. It restricts what *we* may write; it does not exempt us
from the locking protocol, and it is not the same as `immutable=1` (which would
skip locking at the cost of reading a torn database if the WAL moves).

## Fix

Give the reader a timeout and let it wait:

```bash
sqlite3 -readonly ~/.hermes/state.db ".timeout 5000" "select count(*) from messages;"
```

```python
sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=10)
```

Then treat a *persistent* `database is locked` as a real signal rather than
noise: hermes holds an explicit compression lease (`compression_locks`) during
compaction, and a long write legitimately blocks readers for its duration.

Related: an importer that must read a live store should fail the run rather than
skip the session, because a silently skipped session is invisible while a failed
ingest is not.

## Evidence

`session://opencode/ses_e8ca2e501ffeBxfIfKZ5hihPUf#turn-442`

Found by searching the archive for a verbatim phrase from this entry (10 hit(s) for `database is locked`), within 3 days of the entry date.

> 1. First query hit "database is locked" — because hermes is running. Read-only should work but WAL locking can still block. I should retry or use a copy. Worth noting: reading a live SQLite needs retr
