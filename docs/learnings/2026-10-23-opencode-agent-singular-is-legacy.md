# OpenCode V2 silently drops model references under the legacy `agent` key

## Symptom

`~/.config/opencode/opencode.jsonc` set a per-agent model:

```jsonc
"agent": { "plan": { "model": "openrouter/deepseek/deepseek-v4-flash-0731" } }
```

The agent ran the **catalog default** instead (observed `plan · flint-40b-free`).
No error, no warning in the TUI. The only trace is in the server log:

```
level=WARN message="configuration normalization diagnostic"
  path=$.agent.plan.model kind=unsupported
  action="omitted unsupported legacy model reference"
```

`~/.local/share/opencode/log/opencode.log` — filter on
`configuration normalization diagnostic`.

## Cause

V2 renamed the agent-config key to **`agents`** (plural). The singular `agent`
still exists in the schema but is marked `deprecated: true`, and its **model
references** are discarded during normalization rather than migrated. So the
rest of the agent block may appear to work while the model is silently
ignored — which reads as "my model choice does nothing".

## Fix

Use `agents`:

```jsonc
"agents": {
  "plan":  { "model": "deepinfra/deepseek-v4.1-flash-1017#max" },
  "build": { "model": "deepinfra/deepseek-v4.1-flash-1017#low" }
}
```

Verify by running with no `--model`: the footer must name the configured model.
After the fix the warning stops appearing, and `#variant` suffixes resolve
(an unknown variant fails loudly: `Variant unavailable for provider/model: x`,
which is a useful signal that the reference *is* being read).

## Also verified — Deep Infra's `reasoning_effort` enum

Deep Infra's docs list `none | low | medium | high`, but the endpoint accepts
**`none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`**. An integer
(e.g. `100`, as its blog describes "1–100 continuous effort") is **rejected**:

```
422 Input should be 'none', 'minimal', 'low', 'medium', 'high', 'xhigh' or 'max'
```

Probed on `deepseek-ai/DeepSeek-V4.1-Flash-1017`: `max` produced 1620 chars of
reasoning vs 292 for `high` on the same prompt, so the tiers are real. To use
one, define it as a model variant (`variants: [{ id, body: { reasoning_effort } }]`)
and select it as `provider/model#id`.
