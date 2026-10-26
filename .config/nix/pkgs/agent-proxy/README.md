> **Archived 2026-10-25.** This was phase 0 of the memory pipeline and it works,
> but the design dropped it: pi, opencode, hermes and osaurus each already record
> the system prompt, tool schemas, tokens and cost, so capture is now ingest
> rather than interception. Nothing points at this, and nix does not build it.
> Kept because the streaming and SSRF work is sound and wire truth may be wanted
> later. See `~/docs/plans/2026-10-25-agent-memory-pipeline.md` §5.

# agent-proxy

A local, transparent HTTP proxy in front of the model provider. It exists so
that **one** component can capture what every agent harness actually sends and
receives — the exact system prompt, the loaded skills, the tool schemas, the
sampling parameters, token usage and billed cost — instead of writing four
harness-specific integrations and still missing the wire truth.

Phase 0 is deliberately a **pure passthrough**: it captures nothing. It only
proves a request survives the hop unchanged and, critically, that SSE is
forwarded chunk-by-chunk rather than buffered. A buffering proxy would stall
every harness; header rewriting would corrupt streaming or truncate JSON.

Design notes and the full plan: `~/docs/plans/2026-10-25-agent-memory-pipeline.md`.

## Run

```sh
bun run proxy.ts
# [agent-proxy] 127.0.0.1:8787 -> https://api.deepinfra.com
```

| Variable | Default | Meaning |
|---|---|---|
| `AGENT_PROXY_PORT` | `8787` | Port to bind |
| `AGENT_PROXY_HOST` | `127.0.0.1` | Interface to bind — never expose this |
| `AGENT_PROXY_UPSTREAM` | `https://api.deepinfra.com` | Provider **origin**, no path |

`GET /healthz` → `{ok, upstream, uptime_ms}`.

The upstream is an origin and the request path is forwarded verbatim, so the
proxy cannot be turned into an open proxy by a crafted request. Credentials are
never held here: the client's `Authorization` header is forwarded unchanged, so
nothing secret belongs in the nix store.

## Test

```sh
bun test
```

Eight tests against a local mock upstream — no network, no API key, no cost.
They cover byte-identical passthrough, streaming-not-buffering (asserts the
first chunk arrives well before the last), a mid-stream upstream death ending
rather than hanging, a lying `content-length` not truncating the body, and p50
added latency under 20 ms.

## Pointing a harness at it

Change one field each; keep the existing value as a `deepinfra-direct` entry so
there is a one-line switch when the proxy is down.

| Harness | File | Key |
|---|---|---|
| pi | `~/.pi/agent/models.json` | `providers.deepinfra.baseUrl` |
| opencode | `~/.config/opencode/opencode.jsonc` | `provider.<id>.options.baseURL` |
| hermes | `~/.hermes/config.yaml` | `model.base_url` |
| osaurus | `~/.osaurus/providers/remote.json` | `host` + `basePath` + `providerProtocol: http` |

For Deep Infra the path component stays `/v1/openai`, so e.g.
`http://127.0.0.1:8787/v1/openai`.

## Not yet

- No capture, no storage, no redaction (phase 1).
- Not packaged as a nix module or launchd agent (phase 1, after the tests are
  green — developing under `nr` would gate every iteration on a rebuild).
- Not injected into any context (much later; it would need cache-prefix
  discipline, since breaking the cached prefix costs 0.2/M write versus
  0.006/M read on DeepSeek Flash).
