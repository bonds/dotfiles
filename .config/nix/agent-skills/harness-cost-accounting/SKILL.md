---
name: harness-cost-accounting
description: "How each harness here (pi, OpenCode, Hermes) computes a turn's LLM cost, the seam that can change it, and the Deep Infra discount catalogue that makes list price overstate the bill. Use when a harness's reported spend looks wrong, when adding billed-vs-list pricing to a harness, or when you need to find which file computes cost."
---

## When to Use

Use when a harness's reported spend looks wrong ("why is my cost 2x the bill"), when
asked to add billed-vs-list pricing to a harness, when asked to port pi's reported-cost
approach somewhere else ("can we do something similar to pi here?"), or when you need to
find which file computes cost in a given harness. Applies to pi, OpenCode and Hermes; the
seams differ but the defect is the same one.

Every harness on this machine prices a request as `tokens x a configured price`,
never the provider's own invoice. Deep Infra runs per-model standing discounts, so
any list-price table overstates the bill: `billed = list x (1 - discount)`.

Discounts are per model and expire without notice. Read the live catalogue; never
hardcode a multiplier or a price:

```bash
curl -s https://api.deepinfra.com/v1/openai/models
# per entry: metadata.pricing.{input_tokens,output_tokens,cache_read_tokens,cache_write_tokens}
#            metadata.discount      # 0.51 = 51% off -> bill at 0.49x list
```

Key the multiplier by the exact model id the harness sends: in the same family,
`DeepSeek-V4.1-Flash-1017` is discounted 0.51 while `DeepSeek-V4.1-Flash` is 0.30, so
the same token counts are 1.43x or 2.04x overstated depending on which id was used. Resolve
the harness' model string against the catalogue exact-first, then case-insensitively, and
accept a vendor-less tail match only when exactly one entry has it — a loose match silently
prices a sibling at the wrong discount.
Deep Infra publishes no cache-write tier for these models; it bills 0, so a missing
tier is not a pricing gap.

## Where each harness computes cost, and the seam that can change it

| Harness | Cost is computed | Seam | Reads the provider's reported cost? |
|---|---|---|---|
| pi | `tokens x model.cost` from the generated `models.json` | extensions under `.config/nix/pkgs/pi/extensions/` — `reported-cost.ts` rewrites `usage.cost` from `usage.estimated_cost`; `model-prices.ts` renders billed columns | yes, `usage.estimated_cost` per response |
| OpenCode | server-side, from the selected model's `cost` in `opencode.jsonc` | server plugin `~/.config/opencode/plugins/deepinfra-billed-cost.ts` — a model transform, repriced from the catalogue every 30 min and on session start | no — the binary never reads `usage.estimated_cost`, so it must predict the billed rate from the published discount |
| Hermes | `agent/usage_pricing.py::estimate_usage_cost()` → `agent/turn_usage.py` → `state.db` table `session_model_usage` | `ProviderProfile.get_usage_cost()` supplied by a user provider plugin | no — the field is never parsed |

pi's own detail (extension inventory, `models.json`, the `/prices` picker) is in the
`pi-harness` skill — read it there, do not restate it here.

Pitfall (OpenCode): a `cost` in a model definition is merged **after** model transforms
run, so it silently replaces the repriced value with list. Key the model override by the
catalogue id and omit `cost` entirely.

Pitfall (both): cost is computed once per step and history is frozen, so a pricing fix
only affects later steps. A mid-session change produces a mixed total — that is what the
bill does, not a bug.

## Hermes: the seam, and the traps

`estimate_usage_cost()` consults the provider profile **before** its price table:

```python
profile = get_provider_profile(provider or '')
reported = profile.get_usage_cost(model_name, usage) if profile else None
if reported is not None:
    return reported
```

A user provider plugin is a directory under `$HERMES_HOME/plugins/model-providers/<name>/`:

- `__init__.py` — calls `register_provider(profile)` at import time
- `plugin.yaml` — must declare `kind: model-provider`

A working one ships at `~/.hermes/plugins/model-providers/deepinfra/` (Deep Infra at the
billed rate) — read it as the reference implementation. `~/.hermes/` is **not** tracked in
the dotfiles repo, so anything installed there is not reproducible from a fresh checkout;
say so when a result depends on it.

The home layer shadows the bundled profile of the same name
(`layer.registry.get(canonical) or _REGISTRY.get(canonical)`), so a plugin can override a
shipped provider without editing Hermes. `$HERMES_HOME/plugins/` is plain data and survives
`nr`; only `config.yaml` is nix-managed.

Return `CostResult(amount_usd=..., status=..., source=..., label=format_cost_label(amt))`.
`source` must be one of the `CostSource` literals in `usage_pricing.py`. The amount lands in
`estimated_cost_usd` whatever the `status`; `actual_cost_usd` is a reserved column that
nothing in the shipped code writes, so do not try to fill it from a plugin.

`get_usage_cost()` runs on the response path of every turn, so it inherits that path's rules:
**never raise** (return `None` and let the harness' own price table answer), and **never hold
a lock across the catalogue fetch** — a gateway serves turns concurrently, and a hung fetch
would stall every other session behind the mutex. Read and refresh the cache under the lock,
fetch outside it. Only reprice what you can prove: no published discount, a model the
catalogue does not list, or a token bucket it does not rate all return `None`, so the plugin
can never invent a number. Keep the last good catalogue snapshot and stamp the TTL only on a
successful fetch, so a transient failure is retried next turn instead of pinned for the whole
TTL.

**Re-registering a bundled name REPLACES that profile wholesale.** The bundled `deepinfra`
profile also owns `build_api_kwargs_extras()` (the `reasoning_effort` mapping to DeepInfra's
top-level field) and `default_vision_model()`; a fresh profile silently loses both and
reasoning effort stops reaching the wire. Subclass the live instance and copy its `__dict__`
— `ProviderProfile` is a plain, non-frozen, non-slots dataclass, so this works:

```python
base = get_provider_profile("deepinfra")
class Billed(type(base)):
    def get_usage_cost(self, model, usage): ...   # never re-enter estimate_usage_cost()
billed = Billed.__new__(Billed)
billed.__dict__.update(base.__dict__)
register_provider(billed)
```

**The bundled profile may not exist yet when your plugin imports.** A `$HERMES_HOME`
model-provider plugin is imported from inside the home-layer scan, and `hermes_cli.config`
calls `list_providers()` at import time (`_inject_profile_env_vars`), so that scan can run
while `_discover_providers()` is still partway through its bundled pass: `_REGISTRY` is
partially populated and `get_provider_profile("<name>")` returns `None`. Registering nothing
at that moment is a **silent no-op for the whole process** — the module is already in
`sys.modules`, so the scan never re-executes it — and every recorded number stays plausible
at list price. Defer instead: if the bundled profile is missing, wrap
`providers.register_provider` and decorate the profile the moment discovery registers it.

```python
def _arm_late_hook():
    import providers as pkg
    original = pkg.register_provider

    def register_provider(profile):
        original(profile)                    # the bundled registration stands
        _maybe_register(profile, original)   # ours, only if it is the target provider

    pkg.register_provider = register_provider
```

`_maybe_register` must set its registered flag **before** calling through, or the wrapper
re-enters itself. Bundled plugins bind `register_provider` at their own import time and the
target provider has not been imported yet (that is the premise), so it picks up the wrapper.

Never take "the CLI registered fine" as proof the plugin works: a bare
`python3 -c "import agent.usage_pricing"` imports through a different chain and can land in
the early path. Verify the registered profile's identity, not the absence of a warning.

**No plugin hook can change cost.** `VALID_HOOKS` in `hermes_cli/plugins.py` is observers and
transformers of LLM output and tool calls (`post_llm_call`, `transform_llm_output`, ...);
nothing rewrites a pricing entry or a recorded row. Do not hunt for a cost hook — the
provider profile is the only in-process seam.

### The upstream fix, and when to prefer it

Hermes drops the discount in `agent/model_metadata.py::_extract_pricing()`, whose DeepInfra
branch reads `metadata.pricing.{input_tokens,output_tokens,cache_read_tokens}` and ignores
`metadata.discount`. Scaling those rates by `(1 - discount)` there fixes every surface at once
(dashboard analytics, the `display.show_cost` status bar, insights, the `session-cost` plugin)
with nothing local to maintain — and there is no staleness problem, because the `/models`
probe is live with a 300 s TTL, so a discount change lands within five minutes. Prefer this
when you can change the harness; a local plugin is the fallback when you cannot (Hermes here
is a pinned flake input, so a patch means an override in
`modules/packages/hermes-agent-fixed.nix`).

**Two biases, not one.** Hermes documents its own figures as a lower bound
(`dashboard.show_token_analytics`): only successful main-agent responses carrying a
`response.usage` count, so auxiliary calls, retries, fallbacks and cache writes are missed and
the total can be 10x-100x *under* the provider bill. Correcting the rate fixes the
overstatement only. pi escapes the undercount because Deep Infra reports
`usage.estimated_cost` per request; Hermes never parses that field, so a per-turn measurement
like pi's needs that parse added first.

## Reading a nix-packaged harness's source

Answer behaviour questions from the venv in the store, not from the docs:

```bash
readlink -f "$(which hermes)"     # the wrapper; it exports HERMES_PYTHON, HERMES_REVISION, HERMES_BUNDLED_PLUGINS
PY=$(ls -d /nix/store/*-hermes-agent-env/bin/python3 | head -1)
SP=$(ls -d /nix/store/*-hermes-agent-env/lib/python*/site-packages | head -1)
rg -L -n "<symbol>" "$SP"
```

**Every file in that `site-packages` is an individual symlink into the store.** Plain `rg`
and `find -type f` skip symlinks and report zero matches, which reads as "this feature does
not exist". Always pass `-L` (`rg -L`, `find -L`). The `search_files` tool is ripgrep
underneath and shares the blind spot, so a zero-match result from it over a store path
proves nothing — confirm the tool can read the file before concluding absence.

## Verifying the seam

`scripts/hermes-cost-probe.py` prints the cost Hermes computes for a fixed usage, then
re-registers the provider with a billed `get_usage_cost()` and prints it again with the ratio
— the cheapest proof that the seam takes and that the discount is applied:

```bash
PY=$(ls -d /nix/store/*-hermes-agent-env/bin/python3 | head -1)
"$PY" ~/.hermes/skills/dotfiles/harness-cost-accounting/scripts/hermes-cost-probe.py [model-id]
```

Expected: `BEFORE` is tokens x list rate, `AFTER` is `(1 - discount)` of it, and the script
also asserts the bundled profile's other overrides survived the re-registration. A ratio of
`1.0` means the profile was not picked up.

Sanity-check a recorded figure against the DB rather than trusting a UI label —
`session_model_usage` stores per-route tokens plus `estimated_cost_usd`, `actual_cost_usd`,
`cost_status` and `cost_source`, so recomputing `tokens x rate` shows which price the harness
actually used:

```bash
sqlite3 -header -column ~/.hermes/state.db \
  "SELECT model, billing_provider, api_call_count, input_tokens, output_tokens,
          cache_read_tokens, actual_cost_usd, estimated_cost_usd, cost_status, cost_source
     FROM session_model_usage ORDER BY rowid DESC LIMIT 10;"
```

The probe script re-registers the provider itself, so it proves the *seam*, not the installed
plugin. To prove the plugin, assert the registered profile is the subclass and then exercise
a real turn:

```bash
PY=$(ls -d /nix/store/*-hermes-agent-env/bin/python3 | head -1)
"$PY" -c 'from providers import get_provider_profile as g; print(type(g("deepinfra")).__name__)'
hermes chat -q "Reply with exactly: OK"
```

The class name must be the plugin's, not the bundled profile's — an unregistered plugin
prints the bundled class and raises no warning at all. Then recompute the newest
`session_model_usage` row: `recorded / (tokens x list rate)` should be `(1 - discount)`
(`0.70` or `0.49` for the ids above; `1.00` means the plugin did not register). One short
turn writes two rows — the main call and the aux/title call — and both are repriced; the aux
row carries the discounted amount with an empty `cost_source`, so judge it by the ratio, not
by that column.
