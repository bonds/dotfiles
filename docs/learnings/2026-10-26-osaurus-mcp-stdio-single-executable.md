# Osaurus launches a stdio MCP provider as one executable, with no arguments

## Symptom

Adding a custom MCP service in Osaurus with a command *and* an argument:

```
Command: /usr/bin/python3 /Users/scott/tmp/mcp-probe.py
```

failed at the Test step:

```
Status: failed
Reason: spawnFailed
Stage: spawn
Tools: 0
Message: Couldn't launch stdio MCP subprocess: The file "mcp-probe.py" doesn't exist.
```

The file existed and the identical command ran from a shell. The giveaway is in
the wording: it names the **basename**, not the path it was given.

## Cause

The Command field takes a single executable, not a command line. Given two tokens
it resolves one of them and then cannot find the script.

## Fix

Make the entry point an executable with a shebang and no arguments:

```sh
#!/bin/sh
exec /Users/scott/bin/mem mcp "$@"
```

and configure `Command: /Users/scott/bin/mem-mcp`. Verified 2026-10-26: status
`connected`, tools discovered, calls succeed.

This shape is also what other MCP clients want — Claude Desktop and Cursor both
take `command` + `args`, and a single executable works in either — so building the
server behind a shim costs nothing and removes a per-client configuration quirk.
