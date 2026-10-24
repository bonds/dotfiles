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
// The picker only *selects* an agent locally; the switch reaches the server
// when the prompt is submitted, which is when this fires.

import { Plugin } from "@opencode/plugin/tui";

export default Plugin.define({
  id: "agent-model.tui",

  setup(context) {
    const location = context.location ?? context.data.location.default();

    const stop = context.data.on("session.agent.selected", async (event) => {
      const data = event?.data;
      if (!data?.sessionID || !data.agent) return;

      // The prompt selection belongs to the focused session only.
      const route = context.ui.router.current();
      if (route?.type !== "session" || route.sessionID !== data.sessionID) return;

      try {
        await context.data.location.agent.sync(location);
        const agents = context.data.location.agent.list(location) ?? [];
        const want = agents.find((agent) => agent.id === data.agent)?.model;
        if (!want?.variant) return;

        // A deliberately different model keeps its own variant.
        const selected = context.ui.model.current();
        if (!selected) return;
        if (selected.providerID !== want.providerID || selected.modelID !== want.id) return;

        context.ui.model.variant.set(want.variant);
      } catch {
        // A display fix must never break the TUI.
      }
    });

    return () => stop();
  },
});
