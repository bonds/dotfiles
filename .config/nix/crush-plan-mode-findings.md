# Crush 0.99.0 — plan mode, per-slot reasoning effort, and what a crushrc can express

Read-only investigation. Nothing outside the workspace was modified; no activation, no commit.

## Method / evidence base

- Binary: `/nix/store/3whyslr8255gmwrw2yiazsh40zzr3pnm-crush-0.99.0/bin/crush` (`crush version 0.99.0`).
- `strings -a <binary>` — the binary embeds (a) the `crush-config` builtin skill
  (`builtin/crush-config/SKILL.md`, the authoritative config doc), (b) the agent prompts, (c) the
  TUI's user-visible strings and Go symbol names, and (d) its own JSON schema tags.
- The binary also serves its HTTP API docs: `crush server` (started against scratch
  `XDG_CONFIG_HOME`/`XDG_DATA_HOME` inside the workspace, then killed) on
  `unix:///var/folders/.../T/crush-501.sock`; `GET /v1/docs/` and `GET /v1/docs/openapi.json`.
- No keymap table is recoverable from `strings` (help strings and key literals live in separate
  compiler-generated blobs and cannot be paired reliably). Where that matters it is called out.

## 1. Plan Mode — rendered mechanism

Plan mode exists in this build and is the built-in **`plan` agent**, not a separate config surface.

Evidence:

- UI: `PLAN MODE` and `YOLO MODE` badges; `ModeBadgePlan`, `ModeBannerPlan`, `ModeBannerPlanBadge`
  (plus `ModeBadgeYolo`/`ModeBannerYolo`); symbol `internal/ui/model.(*UI).resetPlanModeState`.
- Prompts: `internal/agent.planPrompt` (separate from `internal/agent.coderPrompt`), body starts
  `You are Crush in plan mode`; the plan prompt itself reads the agent map:
  `{{ range $i, $t := (index .Config.Agents "plan").AllowedTools }}`.
- Plan/implementation handoff: `dialog.PlanHandoffInline` (+ `HandleKey`, `runConfirm`,
  `PendingCmd`), `handlePlanHandoff`, `openPlanHandoff`, `planReadySessionID`,
  `PlanStartMarkerPresent` / `PlanReadyMarkerPresent`, markers `<!-- CRUSH_PLAN_START -->` /
  `<!-- CRUSH_PLAN_READY -->`, messages `Plan run completed without ready marker`,
  `Implement the plan.`, and choices labelled `yolo coding` / `revise plan` / `Revise plan`
  (transition symbol `switchPlanToYolo`).
- Errors when it is not set up: `plan agent not configured`, `coder agent not configured`,
  `No agent configuration found`, `agent configuration not found`.
- Api surface (from the binary's own docs): `POST /v1/workspaces/{id}/agent/main`
  — "Set main agent — Switches the workspace's active agent (e.g. \"coder\" or \"plan\")."
  Body: `{"agent_id": "plan"}`. Coordinator symbol: `(*coordinator).SetMainAgent`.

**Keystroke.** I can confirm the binary contains the key literal `shift+tab` and a
default-binding validation message `'shift+tab' is missing.`, and that plan/yolo are the only two
modes shown in the badge — but the help-label blob genuinely contains **no** plan label (the only
labelled mode toggle is `toggle yolo`), so I cannot state the chord with the same certainty as the
rest. Practical answer: you enter/leave plan mode by switching the active agent; the shipped
default chord is `shift+tab`, and the mode badge will read `PLAN MODE` when it takes effect.
Leaving: approve the plan card (badge switches via `switchPlanToYolo`) or switch the agent back.
Verify at runtime rather than trusting this line.

## 2. Is there a separate plan model or plan reasoning effort? — **No**

Three independent pieces of evidence:

```
Model            json:"model"     jsonschema:"required,description=The model type to use for this
                                  agent,enum=large,enum=small,default=large"
Models           json:"models,omitempty"
                 jsonschema:"description=Model configurations for different model types,
                 example={\"large\":{\"model\":\"gpt-4o\",\"provider\":\"openai\"}}"
Provider         json:"provider"  jsonschema:"required,description=The model provider ID that
                                  matches a key in the providers config,example=openai"
```

1. An agent's model is a **slot**, and the enum is exactly `large|small`.
2. The `models` config is keyed by model *type*, and the only documented keys are `large`/`small`
   (`map[config.SelectedModelType]config.SelectedModel` in the symbol table).
3. The crushrc model commands are only `model add`, `model remove`, `model large`, `model small` —
   there is **no `model plan`, no `--plan`, no plan_model** anywhere in the binary.

There is also no `option` key for plan or effort (full list in §4).

## 3. In-session `reasoning_effort` switching — shipped UX

Present in this build (matches upstream #2651 being closed before 0.99.0).

Evidence:

- `dialog.ActionSelectReasoningEffort` and `internal/ui/model.(*UI).openReasoningDialog`.
- Binding id `select_reasoning_effort`; dialog title `Select Reasoning Effort`.
- Result handling: `Reasoning effort set to %s`, `failed to set reasoning effort: %w`.
- Status pill: `Reasoning %s` (next to `Thinking On` / `Thinking Off`).
- Validation at set time: `model %q does not support reasoning effort` and
  `model %q does not support reasoning effort %q, accepted values: %s`.
- Separate non-interactive override: `crush run --reasoning-effort low|medium|high` —
  help text "Reasoning effort for the model (e.g. low, medium, high). Levels depend on the model;
  unsupported values are rejected with the accepted values listed"; log line
  `Overriding reasoning effort for non-interactive run`.

UX shape: a **dialog**, per model (not per message, not a restart). The exact chord is not
recoverable from `strings`; the reliable, version-accurate route is the command palette —
`/` or `ctrl+p` — which lists the entry as **"Select Reasoning Effort"**.

## 4. What a crushrc can express

Builtin set is closed and documented in the embedded skill: **`provider`, `model`, `mcp`, `lsp`,
`hook`, `permissions`, `option`** — there is **no `agent` builtin** (the usage strings for every
builtin in the binary are: `provider add|remove`, `model add|remove`, `mcp add|remove`,
`lsp add|remove`, `hook add|remove`, `permissions allow|deny`, `option reset|ui`).

Full `option` key list (no plan/effort/agent key exists):

```
option <key> [value]
option reset <list-key>                      # clear a list option
Booleans (default true):            debug, debug-lsp, auto-lsp, progress
Booleans phrased positively
  (stored as the negated field):    metrics, auto-summarize, provider-auto-update, default-providers
Strings:                            data-directory, initialize-as, notifications
Attribution:                        attribution-trailer-style none|co-authored-by|assisted-by
                                    attribution-generated-with BOOL
UI:                                 ui compact BOOL, ui diff unified|split, ui transparent BOOL,
                                    ui mouse BOOL, ui scrollbar default|always|never,
                                    ui exit-banner default|compact|none,
                                    ui completions-max-depth N, ui completions-max-items N
List keys (repeatable, one value/call): context-path, global-context-path, skill-path, disable-skill
```

Relevant model flags (verbatim usage strings):

```
usage: model add <provider>/<id> [--name NAME] [--context-window N] [--default-max-tokens N]
    [--thinking always|never|toggleable] [--supports-images true|false] [--price-input F]
    [--price-output F] [--price-cache-create F] [--price-cache-hit F]
    [--reasoning-effort low|medium|high] [--max-attachments N]
usage: provider add <id> [--name NAME] [--type TYPE] [--api-key KEY] [--base-url URL]
    [--disable true|false] [--flat-rate true|false] [--discover-models true|false]
    [--system-prompt-prefix TEXT] [--extra-header KEY VALUE] [--extra-body JSON]
    [--provider-options JSON]
```

So, declaratively:

- **Effort is a property of a model entry / slot, not of an agent or a mode.**
  `model add <provider>/<id> --reasoning-effort …` sets the entry's effort;
  `model large <provider>/<id> [flags]` and `model small <provider>/<id> [flags]` accept
  `--think`, `--reasoning-effort`, `--max-tokens`, `--temperature`, `--top-p`, `--top-k`,
  `--frequency-penalty`, `--presence-penalty`, `--provider-options`.
- **The same model id cannot be registered twice under one provider** — `model add` is keyed by
  `<provider>/<id>` and repeated calls "define/update; repeated calls merge". To get two entries of
  the *same* upstream model at different efforts you must alias the provider: two
  `provider add` ids with the same `--base-url`/`--api-key` (e.g. `deepinfra-max`,
  `deepinfra-low`), then register the same model id under each with different
  `--reasoning-effort`.
- **Not expressible in a crushrc: the agent → slot mapping.** Choosing which slot the `plan` or
  `coder` agent uses lives in the agent config (`agents.<name>.model` ∈ `large|small`) that only
  `crush.json` can carry — and crushrc and crush.json merge, with crushrc winning on conflicts.
- Ceiling: crush's own schema for effort is `enum=low,enum=medium,enum=high`; Deep Infra accepts
  `none|low|medium|high`. There is **no "max"** anywhere — the ceiling is `high`.

## 5. Bottom line for Scott's ask (max effort planning, low effort coding)

**Not expressible as a plan-mode setting**, because plan mode has no model/effort slot of its own —
it is the `plan` agent, which can only point at the `large` or `small` slot.

Closest achievable things:

1. **Declarative (slot split).** Give the two slots different efforts and point the two agents at
   them:
   ```bash
   model large deepinfra/deepseek-ai/DeepSeek-V4.1-Flash-1017 --reasoning-effort high --think
   model small deepinfra/deepseek-ai/DeepSeek-V4.1-Flash-1017 --reasoning-effort low
   ```
   plus, in `crush.json`, `agents.plan.model = "large"` and `agents.coder.model = "small"`.
   Caveat: the docs say `small` is the summarization/title slot, so using it for coding co-opts
   that — and the agent mapping itself is not crushrc-expressible.
2. **Practical, no restart (recommended).** Keep one model and switch effort in-session:
   `/` or `ctrl+p` → **Select Reasoning Effort** → `high` before planning, `low` before
   implementing. That is exactly the shipped UX from #2651 and needs no config tricks.
3. **Scripted/non-interactive:** `crush run --reasoning-effort high|low "<prompt>"`.

Independent of either: `--think` / the thinking toggle is a separate axis from effort, and whether
`DeepSeek-V4.1-Flash-1017` accepts effort at all is model metadata
(`reasoning_levels`, error `no reasoning levels available`) — if it rejects, crush prints the
accepted values verbatim.
