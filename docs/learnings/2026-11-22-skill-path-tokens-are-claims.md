# A `~/…` token in a skill is a claim that the path exists, and `mem doctor` checks it

**Date:** 2026-11-22

## Symptom

After documenting the nightly reports in the `memory` skill, the next `mem doctor` reported `warn  memory: references missing ~/.local/share/agents/memory/reports/YYYY-MM-DD.md` — flagging its own new documentation. The prose meant "one file per night", not a real filename.

## Cause

`mem doctor`'s truth check scans each skill body for `~/…` and `/Users/scott/…` tokens and fails any that do not resolve on disk (`bin/mem`, the `for match in re.finditer(r"(?:~/|/Users/scott/)[A-Za-z0-9._/@+-]+"` loop). It skips tokens containing `<`, `>`, `*`, `$` and the `~/Library` subtrees, but `YYYY-MM-DD.md` contains none of those, so a date placeholder reads as a real path.

## Fix / takeaway

Write the directory (which exists) and describe the filenames in prose instead of embedding a placeholder: "one file per night under `~/.local/share/agents/memory/reports/`, named for the date (`2026-11-21.md`)". A bare relative example is never matched; only `~/` and `/Users/scott/` prefixes are. This check is a feature — it catches a skill that points at a path that moved — so write docs that survive it rather than loosening the regex.
