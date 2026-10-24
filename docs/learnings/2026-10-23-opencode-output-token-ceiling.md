# OpenCode requests a step budget, not the model's output limit

## Symptom

A 1M-context model (`DeepSeek-V4.1-Flash-1017`) compacted mid-turn or failed
around 75% of the window, well before the configured 85% compaction ceiling:

```
This model's maximum context length is 1048576 tokens. However, you requested
1048582 tokens (799027 in the messages, 249555 in the completion).
```

## Cause

Two separate things, both easy to mistake for "OpenCode ignores `limit.output`".

**`limit.output` is a per-step reply budget, not a capability passthrough.**
OpenCode computes each request as

```
maxTokens = min(limit.output, 256_000, context - measured - 15% of estimated)
```

so a model that advertises an output limit as large as its context — Deep Infra
lists `max_tokens == context_length` for *every* model, embedding models
included — never gets asked for all of it. A maintainer's rationale (issue
#29363): using the model maximum could consume the whole window in one turn and
"makes compaction math more annoying". The 256k ceiling itself is
`OUTPUT_TOKEN_MAX`, added in PR #51962 (2026-09-28) precisely because some
models advertise context-sized output.

**On a 1M window that reservation inverts the two ceilings** (issue #58463,
observed on 2.1.4):

- compaction ceiling: `1,048,576 - 15%` = 891,290 (85%)
- request ceiling: `1,048,576 - 256,000` = 792,576 (75.6%)

The request overflows ~98.7k tokens before compaction can fire, so auto-compaction
runs prematurely mid-turn, or a turn fails with `compaction.auto: false`.

Neither the model nor the provider is "the answer" here: OpenRouter's listing
gives `max_completion_tokens: 393216` for this model, models.dev says 384000
(but 16384 for the V4-Pro/V4-Flash siblings), and Deep Infra does not enforce
`max_tokens` at all — `max_tokens: 1048577`, one above the context, returns 200.

## Fix

Set `limit.output` low enough that the request ceiling stays above the
compaction ceiling: anything under ~157k works on a 1M window. We use 64k,
which puts the request ceiling at 984,576 (93.9%) and still leaves room for
long reasoning turns; 32k is the workaround given in the issue and matches v1
behaviour.

```jsonc
"limit": { "context": 1048576, "output": 64000 }
```

Do not set it to the model's advertised maximum, and do not set it to 256k to
"match OpenCode": that pins the reservation at the cap and reproduces the
inversion. A `compaction.buffer` above 256k also fixes the ordering, but it
compacts at ~73% instead of ~89%.

Verify the committed value without piping (the CLI truncates large payloads):

```sh
opencode api get /api/model > /tmp/model.json
jq '.data[] | select(.modelID|test("Flash-1017")) | .limit' /tmp/model.json
```
