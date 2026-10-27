# OpenCode V2 commands silently spawn a background service on a fixed port

**Date:** 2026-10-22

## Symptom

Inspecting a V2 binary from a throwaway `HOME` failed with
`Error: Server process exited with code 1` /
`Managed service port 49374 on 127.0.0.1 is already in use by another process`,
and `opencode debug agents` printed `[]` instead of the configured agents.
Passing `--standalone` after the subcommand gave
`Unrecognized flag: --standalone in command opencode debug`.

## Cause

V2 replaced V1's in-process server with a *managed background service*: most
subcommands (`debug config`, `models`, `debug agents`, the TUI) talk to a daemon
on `127.0.0.1:49374`, spawning it on demand. The port is global, not per-`HOME`,
so a throwaway-`HOME` probe collides with any real instance, and `--standalone`
is a *top-level* flag (`opencode --standalone <sub>`) that the subcommand parser
rejects when placed later. Queries that need the server return empty results
rather than an error when it cannot be reached.

## Fix

For scripted checks that must not touch live state, prefer the commands that
work without the service:

```bash
opencode --version
opencode --help
opencode debug paths     # data/config/cache/state/log/db locations
opencode models          # reads config, prints provider/model lines
```

Treat `[]` from `debug agents` and the port error from `debug config` as "no
service running", not as a broken config. With the real service up the same
queries answer properly — `opencode plugin list` shows a local
`plugins/*.js` file as `local` with its absolute path, and the log records
`msg="loading plugin"`, so local plugins do still load on V2 (the plugin *API*
version is a separate question: `@opencode-ai/plugin` is published only up to
1.19.4, the V1 line). To drive a real instance use `opencode service`
(`set port`, status).

To drive a *different* binary without touching live state, put `--standalone`
**after** the subcommand — `opencode models --standalone`, not
`opencode --standalone models`, which fails with
`Unrecognized flag: --standalone in command opencode models`. Not every
subcommand takes it (`debug` rejects it in either position). `--version` needs
no service at all, and `models --standalone` with a throwaway `HOME` plus a copy
of `~/.config/opencode/opencode.jsonc` is a ~0.6 s config-compatibility probe.

## See also

- [OpenCode V2 ships only through npm](2026-10-22-opencode-v2-is-npm-only.md)

## Evidence

`session://pi/01a166e5-5509-71f0-9f75-d46f5ce3c1fd#turn-89`

Found by searching the archive for a verbatim phrase from this entry (2 hit(s) for `Managed service port 49374 on 127.0.0.1 is already in use by`), within 3 days of the entry date.

> learning({"cause":"V2 replaced V1's in-process server with a *managed background service*: most subcommands (`debug config`, `models`, `debug agents`, the TUI) talk to a daemon on 127.0.0.1:49374, spa
