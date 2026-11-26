# A background server started inside $(...) keeps the substitution open forever

**Date:** 2026-11-26

## Symptom

A test helper `serve() { python3 srv.py & echo ...; }` called as `URL="$(serve)"` hung the whole suite until the command was killed — no output, no error. After the hang was fixed, `kill $SRV_PID` silently did nothing either.

## Cause

Command substitution reads the subshell's stdout until every writer closes it, and the backgrounded server inherited that stdout, so it stayed open for the life of the process. The pid was also lost for the same reason: variables set inside `$(...)` die with the subshell.

## Fix

Redirect the background process (`python3 srv.py > "$T/srv.log" 2>&1 &`) so it holds no inherited stdout, write `$!` to a file for the caller, and call `serve` as a plain function that sets a global instead of `URL="$(serve)"`. Then `kill "$(cat "$T/srv.pid")"`.
