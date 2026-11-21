# Verify billed cost survives a proxy by comparing effective rates per message

**Date:** 2026-11-21

## Symptom

Needed to know whether billion-context's request-rewriting proxy breaks the billed-cost path before installing it, without running a long compression session.

## Cause

pi prices every request as tokens x model.cost and ignores provider-reported cost; `reported-cost.ts` rescales each finished message to Deep Infra's `usage.estimated_cost`. So whether a proxy preserves that field is testable without reading its code: the billed rate is 0.49 x list (discount 0.51), a 2x gap that a broken pass-through would show as the exact list rate.

## Fix / takeaway

Run the same tiny prompt twice and compare effective rates per message: `pi --mode json "Reply with exactly: ok" > base.jsonl`, then the same with the proxy (`pi -e npm:pkg --mode json ...`), and for each assistant `message_end` compute `usage.cost.input / usage.input * 1e6`. Billed shows 0.098/M, list-only shows 0.2/M. A prompt that forces one tool call gives two requests, which also reveals prefix-cache behaviour (`cacheRead` per request).
