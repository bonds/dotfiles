# Deep Infra answers a burst of summary calls with a transient 429, and one 429 used to end the stage

**Date:** 2026-11-26

## Symptom

The nightly report recorded `summarize (budget $0.25) — exit 1` with three lines of `mem: summary request failed: HTTP Error 429: Too Many Requests`, while the sessions after them were never attempted. A bare `hi` request to the same model returned 429 at that moment and 200 a minute later, and re-running the same four sessions summarized them all. So the model, key and budget were fine: 429 was capacity, not quota.

## Cause

api.deepinfra.com returns 429 for a momentary capacity spike, and `chat()` in bin/mem called `die()` on it, which raises SystemExit; the batch loop re-raised that out of the worker, so one rate-limited call aborted every remaining session in the run and the stage failed with money left in its budget.

## Fix

`chat()` retries 429/500/502/503/504 with exponential backoff, honouring `Retry-After` (MEM_SUMMARY_ATTEMPTS, default 4; MEM_SUMMARY_BACKOFF, default 3s), and a worker `die` is counted as a failure instead of aborting the batch, so the stage exits 1 only after the rest of the sessions ran. Repair a bad night with `mem summarize --jobs 2` — never `--force`, which re-bills every session in the archive.
