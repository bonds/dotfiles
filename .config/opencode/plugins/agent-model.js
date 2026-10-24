// Keep a session's model and reasoning effort in step with its agent.
//
// `agents.<id>.model` only chooses the model a session *starts* with: the
// selected model is stored on the session, and switching agents does not
// re-apply it (V2 agents guide: "A session stores its selected model
// separately. Selecting a primary agent by ID does not change that model.").
// Worse, the TUI keeps its own per-session, per-agent model memory and
// re-commits it during the agent-switch submit, so it can undo a server-side
// switch a few milliseconds after it lands.
//
// Two mechanisms, deliberately belt and braces:
//
//   - The request hook is the guarantee. Every agent-loop request gets the
//     agent's configured effort as a request override, so the very first turn
//     after a switch runs at the right effort no matter what the session model
//     or the client did.
//   - The event reconciliation is for the indicator. On `session.agent.selected`
//     the session model is switched to the agent's model, and a conflicting
//     `session.model.selected` inside a short window is corrected, so the
//     footer/model picker converge too. Outside the window a manual model
//     choice is left alone.
//
// The variant values live under `settings.reasoningEffort` in opencode.jsonc,
// not `body`: a raw body overlay is applied after request options and would
// clobber the hook. An agent with no configured model is left alone, and child
// sessions keep their own model.

const CORRECTION_WINDOW_MS = 1000;
const MAX_CORRECTIONS = 2;

export default {
  id: "agent-model",

  async setup(ctx) {
    const controller = new AbortController();
    const here = ctx?.location?.directory;

    // The plugin adapter unwraps a single-property `{ data }` success schema,
    // but tolerate either shape so an adapter change cannot silently disable
    // this.
    const payload = (value) => value?.data ?? value;

    const sameRef = (a, b) =>
      Boolean(a && b) &&
      a.providerID === b.providerID &&
      a.id === b.id &&
      (a.variant ?? "") === (b.variant ?? "");

    // agentID -> configured model ref. The agent config is the single source
    // of truth for both mechanisms, so refresh it when agents change.
    const agents = new Map();
    const loadAgents = async () => {
      try {
        const list = payload(await ctx.agent.list()) ?? [];
        agents.clear();
        for (const agent of list) {
          if (agent?.id && agent.model?.id && agent.model.providerID) {
            agents.set(agent.id, agent.model);
          }
        }
      } catch {
        // Keep the previous map; a failed refresh must not break requests.
      }
    };
    await loadAgents();

    // Guarantee: the request effort follows the agent, whatever the session
    // model says. Only applies while the request uses the agent's configured
    // model, so a deliberately different model is not given Deep Infra knobs.
    let effortHook;
    try {
      effortHook = await ctx.session.hook("context", (event) => {
        const want = agents.get(event.agent);
        if (!want?.variant) return;
        if (event.model?.providerID !== want.providerID || event.model?.id !== want.id) return;
        event.options.reasoningEffort = want.variant;
      });
    } catch {
      // Without the hook the reconciliation below still runs.
    }

    // sessionID -> the model the agent switch asked for, and how long that
    // request stays authoritative.
    const pending = new Map();

    const owns = (session) =>
      !here || !session?.location?.directory || session.location.directory === here;

    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          if (event.type === "agent.updated") {
            await loadAgents();
            continue;
          }

          const data = event?.data;
          if (!data?.sessionID) continue;

          if (event.type === "session.agent.selected") {
            if (!data.agent) continue;
            // One event reaches every loaded location's instance; only the
            // owner acts. The field is optional, and a duplicate switch is a
            // state no-op anyway.
            if (event.location?.directory && here && event.location.directory !== here) continue;

            try {
              const session = payload(await ctx.session.get({ sessionID: data.sessionID }));
              // A subagent session owns its model; it must not inherit the
              // parent's agent selection.
              if (!session?.id || session.parentID || !owns(session)) continue;

              const agent = payload(await ctx.agent.get({ agentID: data.agent }));
              const want = agent?.model;
              if (!want?.id || !want.providerID) {
                pending.delete(data.sessionID);
                continue;
              }

              pending.set(data.sessionID, {
                want,
                until: Date.now() + CORRECTION_WINDOW_MS,
                corrections: 0,
              });
              if (!sameRef(session.model, want)) {
                await ctx.session.switchModel({ sessionID: data.sessionID, model: want });
              }
            } catch {
              // A failed switch must not end the subscription.
            }
            continue;
          }

          if (event.type !== "session.model.selected") continue;

          // The TUI commits its own selection right after an agent switch. If
          // that write lands after ours, put the agent's model back — but only
          // inside the window, so a later manual choice is respected.
          const intent = pending.get(data.sessionID);
          if (!intent) continue;
          if (Date.now() > intent.until) {
            pending.delete(data.sessionID);
            continue;
          }
          if (sameRef(data.model, intent.want)) continue;
          if (intent.corrections >= MAX_CORRECTIONS) {
            pending.delete(data.sessionID);
            continue;
          }

          intent.corrections += 1;
          try {
            await ctx.session.switchModel({ sessionID: data.sessionID, model: intent.want });
          } catch {
            // Keep the subscription alive even if the correction fails.
          }
        }
      } catch {
        // Subscription ends when the plugin unloads.
      }
    })();

    return async () => {
      controller.abort();
      await effortHook?.dispose?.();
    };
  },
};
