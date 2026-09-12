# SKILL.md — osaurus-spend

When the user asks how much they've spent on AI/LLM usage, per session or per
time range, use the **`spend_report`** tool from the `com.ggr.osaurus-spend`
plugin. Do not guess from memory or estimate — run the tool.

## What it returns

A JSON report with:

- **`providers`** — authoritative USD totals, pulled live from the provider
  APIs using keys read from the macOS Keychain (service `ai.osaurus.remote`,
  the same store Osaurus itself uses — no keys are hardcoded or stored in the
  plugin):
  - `openrouter`: exact USD for the chosen range (`GET /api/v1/key` →
    `usage_daily` / `usage_weekly` / `usage_monthly` / `usage`).
  - `deepinfra`: USD for the overlapping month(s) (`GET /payment/usage`,
    DeepInfra is monthly-granularity only).
  - `router`: exact Osaurus Router ledger totals (empty until hosted Router
    is used).
- **`local`** — per-provider session/turn/output-token aggregates read from
  `~/.osaurus/chat-history/history.sqlite`.
- **`sessions`** — one row per session: title, created, model, provider, turn
  count, output tokens, and `cost_usd` (only set for Router sessions).

## Time ranges

`time_range` ∈ `this_session | today | 7d | 30d | all` (default `today`).

- `this_session` resolves to the **most recently active** session (the plugin
  has no direct handle on the running session id).
- `7d` / `30d` map to OpenRouter's weekly / monthly totals.
- `today` on DeepInfra reports the whole current month (month-to-date), since
  DeepInfra has no day-level endpoint.

## Data honesty (important)

Exact per-session USD is **only** recorded when a session runs through Osaurus
Router (host stores input/output tokens + cost in `router_billing`). For
OpenRouter/DeepInfra sessions the host only records **output** token counts, so
`cost_usd` is `null` and input tokens are unavailable. Always present the
caveats verbatim so the user isn't misled into thinking a per-session figure is
exact. Prefer reporting the provider totals (exact) alongside the per-session
token counts.

## Build / iterate (local dev)

From `~/.config/nix/pkgs/osaurus-spend`:

```sh
swift build --disable-sandbox          # builds .build/debug/libosaurus-spend.dylib
# smoke test (manifest + real invoke):
swiftc -o .smoketest/run .smoketest/main.swift
.smoketest/run .build/debug/libosaurus-spend.dylib '{"time_range":"7d"}'
```
