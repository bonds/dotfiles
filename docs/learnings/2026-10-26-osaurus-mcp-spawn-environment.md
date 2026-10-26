# Osaurus spawns MCP servers with `cwd=/` and a minimal environment

## Symptom

A stdio MCP shim that read `$HOME` worked when Osaurus launched it, and failed
under a stripped environment:

```
$ env -i /Users/scott/bin/mem-mcp
/Users/scott/bin/mem-mcp: line 8: /bin/mem: No such file or directory
```

`$HOME` was empty, so `exec "$HOME/bin/mem"` became `exec /bin/mem`. It only
worked under Osaurus because Osaurus happens to pass `HOME` — luck rather than
design.

## Cause

Osaurus does not spawn MCP children from a login shell. A probe tool reported
`cwd=/`, which is the tell: no inherited working directory, so nothing about the
environment should be assumed. `PATH` is the same hazard — `mem`'s shebang is
`#!/usr/bin/env python3`, which needs a `PATH` to resolve.

## Fix

Pin everything the shim needs:

```sh
#!/bin/sh
PATH=/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}
export PATH
exec /Users/scott/bin/mem mcp "$@"
```

Test any new MCP entry point with `env -i <shim>` before wiring it into a client.
Verified 2026-10-26: `tools/list` answers and a real `learnings` call returns
entries under a bare environment.

## Why it matters more than it looks

An MCP server that fails to launch gives the agent **no error and no memory** — it
simply knows less than it should, and nothing in the transcript says so. A crash
would be kinder.
