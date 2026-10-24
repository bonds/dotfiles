// Keep a session's model in step with its agent's configured model.
//
// `agents.<id>.model` only chooses the model a session *starts* with: the
// selected model is stored on the session, and switching agents does not
// re-apply it. The V2 agents guide is explicit — "A session stores its
// selected model separately. Selecting a primary agent by ID does not change
// that model." So a session begun in Build stays on Build's #low when it
// switches to Plan, and per-agent effort settings never take effect.
//
// This plugin closes that gap: on `session.agent.selected`, apply the agent's
// own model ref through `session.switchModel`. The config stays the single
// source of truth. An agent without a configured model is left alone (it
// inherits), and child sessions keep their own model.

export default {
  id: "agent-model",

  setup(ctx) {
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

    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          if (event.type !== "session.agent.selected") continue;
          const data = event.data;
          if (!data?.sessionID || !data.agent) continue;
          // One event reaches every loaded location's instance; only the owner
          // acts. The field is optional, and when it is missing the session
          // check below still makes a duplicate switch a no-op.
          if (event.location?.directory && here && event.location.directory !== here) continue;

          try {
            const session = payload(await ctx.session.get({ sessionID: data.sessionID }));
            // A subagent session owns its model; it must not inherit the
            // parent's agent selection.
            if (!session?.id || session.parentID) continue;
            // Authoritative owner check: every loaded location receives the
            // event, but only the one whose directory owns this session may
            // switch it. Falls back to the event filter when either is absent.
            if (here && session.location?.directory && session.location.directory !== here) continue;

            const agent = payload(await ctx.agent.get({ agentID: data.agent }));
            const want = agent?.model;
            if (!want?.id || !want.providerID) continue;
            if (sameRef(session.model, want)) continue;

            await ctx.session.switchModel({ sessionID: data.sessionID, model: want });
          } catch {
            // A failed switch must not end the subscription.
          }
        }
      } catch {
        // Subscription ends when the plugin unloads.
      }
    })();

    return () => controller.abort();
  },
};
