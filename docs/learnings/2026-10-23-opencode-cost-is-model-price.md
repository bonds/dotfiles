# OpenCode's cost is the model's configured price, not the provider's bill

## Symptom

A session running Deep Infra's `DeepSeek-V4.1-Flash-1017` reported roughly
**2× the actual bill**. The TUI session total, the `$x.xx` summaries, and the
stats all agreed with each other — and all were too high.

## Cause

OpenCode computes a step's cost itself, in the server, at
`session.step.ended`:

```
(input*price.input + (output+reasoning)*price.output
 + cache.read*price.cache.read + cache.write*price.cache.write) / 1e6
```

where `price` is the selected model's `cost` from `opencode.json(c)`. It never
reads the provider's `usage.estimated_cost` (`rg -a estimated_cost` over the
binary has **zero** matches), so a standing provider discount is invisible.

Deep Infra's catalogue carries the missing data:

```json
"pricing": { "input_tokens": 0.2, "output_tokens": 0.6, "cache_read_tokens": 0.006 },
"discount": 0.51
```

`discount` is the **fraction off**, not a multiplier. Measured against a live
response: list cost 0.0000172, `usage.estimated_cost` 0.000008428 — a ratio of
exactly 0.49. So billed = list × (1 − discount).

## Fix

A server plugin (`plugins/deepinfra-billed-cost.ts`) registers a model
transform that reprices each Deep Infra model **from its own catalogue
entry**: `metadata.pricing` (the billed base) scaled by
`(1 - metadata.discount)`, falling back to scaling the configured price when
the catalogue omits pricing. Discounts are per model — currently 9 of 175
models are discounted, at 10%–75% — so the map is keyed by `modelID` and
models with no discount are left alone. It refreshes every 30 minutes and on
`session.execution.started` (rate-limited to once a minute). Cost is computed
*once per step*, so:

- history is frozen — recorded costs are never re-priced;
- a price change only affects steps taken afterwards;
- a mid-session change produces a mixed total, which is what the bill does.

Transforms replay from the source definition, so scaling the configured price
cannot compound across reloads. Failure to fetch the catalogue leaves the
configured (list) prices in force.

Verify: `session_message.data` stores per-step `cost` + `tokens` (and
`session_v2.cost` the running total), so

```
list = (in*0.2 + (out+reasoning)*0.6 + cache_read*0.006 + cache_write*0.2)/1e6
```

should equal `cost / 0.49` for a newly recorded step.
