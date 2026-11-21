# pi's cost seam is `message_end`, and a third-party footer inherits the rewrite for free

**Date:** 2026-11-21

## Symptom

Installed `pi-fast-tui` (a footer/header/telemetry replacement) on top of
`reported-cost.ts`, which rescales each message's `usage.cost` to Deep Infra's
billed `estimated_cost`. Expected the new footer to reintroduce list prices, or
to need its own pricing hook. It showed billed numbers with no changes:
`$` footer total and the `$/M` telemetry rate both matched `/session`.

## Cause

Cost is born in one place and rewritten at one boundary, so anything that reads
the session store inherits the rewrite:

- `pi-ai/dist/models.js::calculateCost(model, usage)` is the only place a price
  is applied. Each adapter calls it after parsing usage
  (`api/openai-completions.js:1186`, `api/anthropic-messages.js:699`); it
  mutates `usage.cost` in place and stamps `cost.totalFromProvider = false`.
- `message_end` may return `{ message }` to *replace the finalized message*,
  and it runs before pi persists the entry and before session totals are
  computed (`docs/extensions.md:758`). Rewriting `usage.cost` there is therefore
  what every store reader sees: `core/usage-totals.js::addUsageToTotals`,
  `getUsageCostBreakdown(entries)`, HTML export, and any extension that
  re-derives totals from `sessionManager.getEntries()` — which is exactly what
  pi-fast-tui does (`src/ui/state.ts:40`, `src/ui/telemetry.ts:257`).
- Because those readers re-read the store, **hook order between extensions does
  not matter**. It only matters for a *chained* handler: later `message_end`
  handlers receive the earlier handler's returned value
  (`docs/extensions.md:420`), so an extension that computes cost inside
  `message_end` sees billed numbers only if `reported-cost.ts` loaded first.

pi already has the intended shape for this: `pi-ai/dist/utils/openrouter-cost.js::applyOpenRouterReportedCost`
overwrites `cost.total` from the provider's `cost` field **and sets
`cost.totalFromProvider = true`**, gated on `model.provider === "openrouter" ||
model.baseUrl.includes("openrouter.ai")`. Deep Infra matches neither, so
`reported-cost.ts` is filling an adapter gap, not fighting the harness. It
originally left the flag `false`, which made `usage-totals.js::combineUsage`
("a sum is provider-reported only when every part is") label a billed number as
a catalog estimate — fixed by setting the flag alongside the rewrite.

### Where the seam does not reach

- **Cache warming bypasses the message path.** `core/cache-warmer.js:188` calls
  `models.streamSimple` directly, outside the agent loop, and records a `usage`
  entry with `kind: "cache_warm"` — no assistant message, so no `message_end`,
  so list price in the store. Readers that sum `entry.type === "usage"` (fast-tui
  does) will include it.
- **`branch_summary` and `compaction` entries** carry their own `usage`,
  computed by pi, never rewritten.
- **`toolResult.usage`** (codemode / subagent tool usage) likewise.
- **`cache_warming_decision` economics are list-priced.**
  `pi-ai/dist/cache-warming.js:80` computes `warmCost`/`missCost` with
  `calculateCost`, so on a 0.51-discount model pi's warm-vs-stop decision is
  calibrated on ~2x the real cost — a behavioural bias, not just a wrong label.
- `provider_stream_event` is notification-only, "read-only", and not persisted
  (`docs/extensions.md:899`), which is why the capture and the write have to be
  two separate hooks.

## Fix

Rewrite `usage.cost` in `message_end` and set `cost.totalFromProvider = true`
with it. Then verify with arithmetic rather than the UI: list is tokens x the
`models.json` rates, and the persisted ratio must be `1 - discount`.

```fish
jq -r 'select(.type=="message" and .message.role=="assistant") | .message.usage
       | "\(.input)\t\(.output)\t\(.cacheRead)\t\(.cost.total)"' $PI_SESSION_FILE
# ratio = cost.total / ((input*0.2 + output*0.6 + cacheRead*0.006)/1e6)
# 0.490 for DeepSeek-V4.1-Flash-1017 (discount 0.51); 1.0 means list price survived
```

Related: `docs/learnings/2026-11-17-hermes-cost-is-list-price.md` (same defect
class, different seam) and
`docs/learnings/2026-11-21-verifying-billed-cost-through-a-proxy.md`.
