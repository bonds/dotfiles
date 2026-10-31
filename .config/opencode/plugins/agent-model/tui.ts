// Keep the TUI's prompt selection in step with the agent.
//
// The footer/model indicator renders the TUI's own prompt selection, not the
// session's model. The server-side agent-model plugin keeps the session model
// and the requests correct, but a server-side `switchModel` never moves the
// TUI's selection — and the TUI re-commits that stale selection on submit, so
// the indicator can keep showing the previous variant.
//
// `context.ui.model.variant` is the documented way to move that selection, and
// it is reactive, so setting it here updates the footer and the model the TUI
// commits on submit. Only the focused session's prompt is touched, and only
// while it is on the agent's configured model.
//
// The TUI remembers one variant per model, globally, in
// ~/.local/state/opencode/model.json, so the composer keeps claiming the last
// agent's effort until something corrects it. Three triggers, one per way the
// composer can end up on the wrong variant:
//
//   - `session.agent.selected`: the picker only selects an agent locally; the
//     switch reaches the server when the prompt is submitted, which is when
//     this fires.
//   - `session.created`: a session that *starts* on an agent (the default
//     agent, or `session.create` with an agent) never emits a selection.
//   - the home screen: there is no session yet, so nothing fires at all. A
//     home prompt runs as the agent the TUI last used (seeded by
//     `default_agent` at the start of a run), which the two triggers above
//     already reveal, so remember it and align on arrival at home. Only the
//     home route is touched — a session owns its own model.
//
// There is no plugin API for the agent currently picked in the composer before
// a submit, so a pick that has not reached the server yet cannot be followed.

import { Plugin } from "@opencode/plugin/tui";

export default Plugin.define({
  id: "agent-model.tui",

  setup(context) {
    const location = context.location ?? context.data.location.default();

    // Point the composer's variant at the agent's configured one. Returns true
    // once the composer and the agent are both available (whether it acted or
    // had nothing to do), false when it is too early to tell — the caller may
    // retry.
    const align = (agentID) => {
      try {
        const agent = (context.data.location.agent.list(location) ?? []).find(
          (candidate) => candidate.id === agentID,
        );
        if (!agent) return false;

        const selected = context.ui.model.current();
        if (!selected) return false;

        // An agent with no model of its own, or no variant, has nothing to
        // align.
        const want = agent.model;
        if (!want?.id || !want.providerID || !want.variant) return true;

        // A deliberately different model keeps its own variant.
        if (selected.providerID !== want.providerID || selected.modelID !== want.id) return true;

        if (selected.variant !== want.variant) context.ui.model.variant.set(want.variant);
        return true;
      } catch {
        // A display fix must never break the TUI.
        return true;
      }
    };

    const route = () => context.ui.router.current();
    const focused = (sessionID) => {
      const current = route();
      return current?.type === "session" && current.sessionID === sessionID;
    };

    // The agent the TUI will use for the next prompt. Seeded from
    // `default_agent` (which is what a run starts on) and then updated from
    // what the user actually selects, because the home screen's agent follows
    // the last session, not the configured default.
    let knownAgent;

    const stops = [];

    stops.push(
      context.data.on("session.created", async (event) => {
        const data = event?.data;
        if (!data?.sessionID) return;
        // A subagent session owns its model; it must not inherit the parent's
        // agent selection.
        if (data.parentID) return;
        if (data.location?.directory && location?.directory) {
          if (data.location.directory !== location.directory) return;
        }

        // `agent` is optional on the event: read it back from the session when
        // the creator left it to the default.
        let agentID = data.agent;
        if (!agentID) {
          try {
            await context.data.session.sync(data.sessionID);
            agentID = context.data.session.get(data.sessionID)?.agent;
          } catch {
            return;
          }
        }
        if (!agentID) return;

        // Focused: the composer now belongs to this session. Home: the session
        // was just created from the home composer, and the event can land
        // before the TUI navigates, so the composer is still the right target.
        if (!focused(data.sessionID) && route()?.type !== "home") return;

        knownAgent = agentID;
        align(agentID);
      }),
    );

    stops.push(
      context.data.on("session.agent.selected", async (event) => {
        const data = event?.data;
        if (!data?.sessionID || !data.agent) return;

        // The prompt selection belongs to the focused session only.
        if (!focused(data.sessionID)) return;

        try {
          await context.data.location.agent.sync(location);
        } catch {
          // The cached list is usually good enough.
        }
        knownAgent = data.agent;
        align(data.agent);
      }),
    );

    // The home screen has no session yet, so `session.created` cannot correct
    // it — the composer sits on whatever `~/.local/state/opencode/model.json`
    // remembered for the model, and claims a different agent's effort until
    // the first submit. A home prompt runs as the agent the TUI last used (not
    // `default_agent`, which only seeds the first session of a run), so track
    // that from the events above and use `default_agent` as the seed.
    //
    // The router has no subscription and `current()` is not reactive, so this
    // has to poll. It acts on the transition *to* home, so a variant picked by
    // hand on the home screen is left alone.
    let stopped = false;
    let timer;
    let lastType;
    let lastSession;
    let pending = false;

    const watch = () => {
      if (stopped) return;

      const current = route();
      const type = current?.type;

      // Opening a session moves the TUI's remembered agent to that session's.
      if (type === "session" && current.sessionID !== lastSession) {
        lastSession = current.sessionID;
        const agent = context.data.session.get(current.sessionID)?.agent;
        if (agent) knownAgent = agent;
      }

      if (type === "home" && lastType !== "home") pending = true;
      lastType = type;

      // Retried until the composer is mounted; `align` reports when it is.
      if (pending && knownAgent && align(knownAgent)) pending = false;

      timer = setTimeout(watch, 1000);
    };

    void (async () => {
      try {
        const result = await context.client.config.get();
        // One entry per config document, in load order; the last one that sets
        // the key wins.
        for (const entry of (Array.isArray(result) ? result : result?.data) ?? []) {
          if (entry?.info?.default_agent) knownAgent = entry.info.default_agent;
        }
      } catch {
        // Without a seed the watcher simply never aligns.
      }
      if (!knownAgent) return;

      try {
        await context.data.location.agent.sync(location);
      } catch {
        // The cached list is usually good enough.
      }
      watch();
    })();

    return () => {
      stopped = true;
      clearTimeout(timer);
      stops.forEach((stop) => stop());
    };
  },
});
