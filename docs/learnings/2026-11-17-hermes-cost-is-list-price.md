# Hermes prices Deep Infra at list, and a `$HERMES_HOME` provider plugin is where you fix it

**Date:** 2026-11-17

## Symptom

Every Deep Infra session in `~/.hermes/state.db` overstated the bill. A turn
recorded 0.0026524904 for 18922 in / 3 out / 512 cache-read; the list-rate
computation `(in*0.2 + out*0.6 + cache_read*0.006)/1e6` is 0.003789272 — exactly
`recorded / 0.7`. `cost_status` was `estimated`, `cost_source`
`provider_models_api`, and `actual_cost_usd` was 0. The same 0.7/0.49 factor
showed on the aux (titling) call and on `hermes insights`.

## Cause

Three separate facts, all in the shipped Hermes 0.21.5 venv:

- **The discount is dropped on read.** `agent/model_metadata.py::_extract_pricing()`
  has an explicit Deep Infra branch —

  ```python
  deepinfra_fields = {"prompt": "input_tokens", "completion": "output_tokens", "cache_read": "cache_read_tokens"}
  ```

  — reading `metadata.pricing` out of the `/models` payload and never reading
  `metadata.discount` beside it. The catalogue entry for
  `deepseek-ai/DeepSeek-V4.1-Flash` is `pricing {0.2, 0.6, 0.006}` with
  `discount 0.3` (the `…-1017` carries 0.51), so the extracted rate is list and
  the recorded figure is `1/(1-discount)` too high.
- **The provider's own number is never read.** Nothing in the venv parses
  `usage.estimated_cost` (no occurrences), so `actual_cost_usd` is only ever a
  parameter nothing passes.
- **No plugin *hook* can touch cost.** `VALID_HOOKS` in `hermes_cli/plugins.py`
  is LLM-output and tool-call observers/transformers; the cost is computed in
  `agent/usage_pricing.py` and written by `agent/turn_usage.py`.

The seam is that `estimate_usage_cost()` consults the **provider profile first**,
ahead of any price table:

```python
profile = get_provider_profile(provider or '')
reported = profile.get_usage_cost(model_name, usage) if profile else None
if reported is not None:
    return reported
```

and `providers/__init__.py` loads `$HERMES_HOME/plugins/model-providers/<name>/`
into a per-home layer that shadows the bundled profile of the same name.

## Fix

`~/.hermes/plugins/model-providers/deepinfra/` — `plugin.yaml`
(`kind: model-provider`) plus an `__init__.py` that re-registers `deepinfra`
with `get_usage_cost()` implemented as catalogue `metadata.pricing` ×
`(1 - metadata.discount)`. Models with no discount, unrated token buckets and a
failed fetch all return `None`, which leaves Hermes' own list-price path in
place. The catalogue is cached 300 s, the TTL Hermes uses for its own probe.

Verified: two live sessions recorded exactly 0.7 × list on both the main and the
aux row, and `hermes insights` follows. Check it with

```fish
sqlite3 ~/.hermes/state.db "SELECT input_tokens, output_tokens, cache_read_tokens, \
  estimated_cost_usd FROM session_model_usage ORDER BY rowid DESC LIMIT 2"
# recorded should be 0.7x (DeepSeek-V4.1-Flash) or 0.49x (…-1017) of the list math
```

### Two traps, both hit while building it

**Registering a profile under an existing name replaces it wholesale.** The
bundled `_DeepInfraProfile` also owns `build_api_kwargs_extras` (the
reasoning-effort → Deep Infra `reasoning_effort` mapping) and
`default_vision_model`; a fresh profile silently loses both. Subclass the live
bundled instance and copy its `__dict__` instead:

```python
subclass = type("_DeepInfraBilledCostProfile", (type(base),), {"get_usage_cost": get_usage_cost})
profile = subclass.__new__(subclass)
profile.__dict__.update(base.__dict__)
register_provider(profile)
```

**The bundled profile is not always registered when your plugin imports.** A
bundled plugin imported before `deepinfra` alphabetically pulls in
`hermes_cli.plugins` → `hermes_cli.config`, whose import-time
`_inject_profile_env_vars()` calls `list_providers()` → `_home_layer()` → the
`$HERMES_HOME` scan. Your module then executes *inside* `_discover_providers()`
with a partially populated `_REGISTRY`, and `get_provider_profile("deepinfra")`
returns `None`. Registering nothing there is a **silent no-op for the whole
process** — the module is already in `sys.modules`, so the scan never
re-executes it, and the numbers look plausible at list price. (Observed
directly: `hermes chat -q` registered fine, a bare `python3 -c "import
agent.usage_pricing"` did not.) The plugin therefore wraps
`providers.register_provider` when the profile is missing, and decorates the
bundled profile the moment discovery registers it.

A third, smaller one: `get_usage_cost` runs on the response path of every turn,
so the catalogue fetch must not hold the module lock — a cold or hung fetch
would stall every concurrent gateway turn behind the mutex. Read/refresh state
under the lock, fetch outside it.

## Why not upstream

The one-line fix is in `_extract_pricing()` (scale by `1 - discount`), and it
would fix `insights`, the dashboard analytics and the `display.show_cost` status
bar at once. It is not available today: hermes-agent is a pinned flake input
(`inputs.hermes-agent`, rev `749220ef`), so a local patch means overriding the
package in `modules/packages/hermes-agent-fixed.nix` and carrying it until a PR
lands. The plugin needs no flake edit and lives in `$HERMES_HOME`, which is
plain data — but note `~/.hermes/` is **not** tracked in this repo, so the
plugin is not reproducible from dotfiles. Upstream is the durable fix; this is
the one that works now.

Related: `docs/learnings/2026-10-23-opencode-cost-is-model-price.md` — same
defect class in OpenCode, fixed there by a server plugin that reprices each
model from the same catalogue.
