# osaurus-spend

Local Osaurus plugin exposing the **`spend_report`** tool: how much you've
spent on LLM providers across Osaurus sessions, for a chosen time range.

- **Exact USD totals** come live from provider APIs using API keys read from
  the macOS Keychain (service `ai.osaurus.remote`, the same store Osaurus
  uses — no keys are hardcoded):
  - OpenRouter `GET /api/v1/key` (daily / weekly / monthly / all-time)
  - DeepInfra `GET /payment/usage` (monthly)
  - Osaurus Router ledger (`~/.osaurus/billing/ledger.sqlite`, exact per-session)
- **Per-session stats** (title, model, provider, turns, output tokens) come from
  `~/.osaurus/chat-history/history.sqlite`.

`time_range`: `this_session | today | 7d | 30d | all` (default `today`).

## Data honesty

Exact per-session USD is only recorded for Osaurus **Router** sessions. For
OpenRouter/DeepInfra the host records only output-token counts, so per-session
`cost_usd` is `null` and input tokens aren't available. The tool reports exact
provider totals alongside per-session token counts and returns caveats explaining
this. See `SKILL.md` for full details.

## Build

```sh
swift build --disable-sandbox   # -> .build/debug/libosaurus-spend.dylib
```

(`--disable-sandbox` is needed because this environment forbids the manifest
sandbox; the canonical `swift build` scaffold also fails to compile under the
current Swift 6.2 toolchain without the fixes in `Plugin.swift`.)

## Smoke test

```sh
swiftc -o .smoketest/run .smoketest/main.swift
.smoketest/run .build/debug/libosaurus-spend.dylib '{"time_range":"7d"}'
```

The harness loads the dylib, checks the manifest is valid JSON, then invokes
`spend_report` with real data (keychain, provider APIs, local DB).

## Install

```sh
# from the plugin root
osaurus tools dev com.ggr.osaurus-spend   # dev mode / hot reload
# or package + install
osaurus tools package com.ggr.osaurus-spend 0.1.0 .build/debug/libosaurus-spend.dylib
osaurus tools install ./com.ggr.osaurus-spend-0.1.0.zip
```
