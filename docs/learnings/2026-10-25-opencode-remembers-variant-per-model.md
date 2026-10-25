# OpenCode remembers a variant per model, and `default_agent` emits no selection

## Symptom

Every new session opened in plan mode showed — and recorded — `low` effort even
though the plan agent is configured `#max` in `opencode.jsonc`:

```jsonc
"agents": {
  "plan":  { "model": "deepinfra/deepseek-ai/DeepSeek-V4.1-Flash-1017#max" },
  "build": { "model": "deepinfra/deepseek-ai/DeepSeek-V4.1-Flash-1017#low" }
}
```

The `agent-model` plugin, whose whole job is to keep a session's effort in step
with its agent, never fired for those sessions.

## Cause

Two independent facts.

**The TUI stores the variant per model, globally.** `~/.local/state/opencode/model.json`
keeps one variant per `providerID/modelID`:

```json
"variant": { "deepinfra/deepseek-ai/DeepSeek-V4.1-Flash-1017": "low" }
```

A new session's prompt is seeded from that remembered value, not from the
agent's model. So whichever agent ran last decides where the next session
starts: ending a session on build (`low`) makes the next plan session `low`.

**A session that starts on an agent emits no selection event.** `session.agent.selected`
fires only when an agent is actually *switched*. With `"default_agent": "plan"`,
sessions simply begin on plan, so the plugin's reconciliation — which was wired
to that event only — never ran. The same is true of `session.create` with an
explicit agent.

Corollary: `session.created` carries `agent` and `model`, and its `agent` field
is optional (absent when the creator left the agent to the default), so a
consumer must read it back from the session rather than trust the event.

## Why it looked worse than it was

The requests themselves were already correct. The `session.hook("context")`
override reaches the wire even when the session model disagrees — verified by
temporarily hooking `session.hook("http.request")` and logging the cloned body:

```
context: model.variant=low  configured=max
HTTP:    reasoning_effort: "max"
```

So the session model's `variant` is **not** authoritative for effort; the
request hook is. A wrong variant is a wrong *label* and a wrong *record*, not a
wrong bill.

## Fix

Handle `session.created` in **both** halves, alongside the existing
`session.agent.selected`:

- **TUI** (`plugins/agent-model/tui.ts`): resolve the session's agent and, when
  the composer is on that agent's configured model, set `ui.model.variant` to
  the agent's variant. The route is not necessarily on the new session when the
  event lands, so treat `home` as a target too — the home composer is what
  created it.
- **TUI, home screen**: there is no session yet, so nothing fires at all and
  the footer lies until the first submit. A home prompt runs as the agent the
  TUI **last used** — `default_agent` only seeds the first session of a run —
  so track that from the two events above, seeded by `default_agent`, and align
  on arrival at home. The router exposes no subscription and `current()` is not
  reactive, so a 1s poll is the only option; acting only on the transition
  keeps a hand-picked variant on the home screen intact.

  Getting this wrong is easy and visible: aligning the home screen to
  `default_agent` instead of the last agent rewrites a build composer to the
  plan variant, and the wrong effort is then the plugin's fault rather than the
  TUI's.
- **Server** (`plugins/agent-model/index.ts`): `switchModel` the session to the
  agent's model so the *record* is right from the first turn, not just the
  wire. Only when the session already chose the same provider/model — a
  deliberately different model keeps its own variant — and the existing
  correction window absorbs a stale client commit.

Align once per session, so a variant picked by hand mid-session still sticks
until the next agent switch.

Remaining gap: the TUI plugin API has no getter for the agent currently picked
in the composer. Picking an agent only reaches the server on submit, so a
footer that should change the moment the picker closes still cannot — that
needs opencode to expose the selection (or to emit `session.agent.selected`
when the picker changes, not on submit).

## Check it

```bash
python3 -c "import json;print(json.load(open('$HOME/.local/state/opencode/model.json'))['variant'])"
```

Open a new session: the entry for the model should move to the default agent's
variant (`max`), not stay on whatever the last build session left (`low`).

Server side, a session created on the wrong variant is corrected immediately:

```bash
opencode api post /api/session -d '{"agent":"plan","model":{"id":"deepseek-ai/DeepSeek-V4.1-Flash-1017","providerID":"deepinfra","variant":"low"}}'
opencode api get /api/session/<id>   # model.variant is now "max"
```
