/**
 * Auto Compact — compress context at a stopping point, never mid-task.
 *
 * pi's built-in auto-compaction is threshold-only and fires as soon as the
 * projection crosses `contextWindow - reserveTokens`: after a tool batch,
 * before the next assistant response — i.e. mid-task. On the 1M DeepSeek model
 * the default reserve (16384) puts that at ~1.03M, so it is a last-resort net
 * rather than a maintenance step.
 *
 * `agent_settled` fires only once a run is *fully* settled — no retry, no
 * queued continuation, no pending compaction — which is exactly "finished, or
 * waiting on the user". That is the moment worth paying a summary call at.
 *
 * Mechanics: `ctx.compact()` reaches `session.compact()`, which aborts first;
 * harmless here because the session has already cleared its run-active flag.
 * It does not consult `compaction.enabled`, so the built-in threshold stays
 * untouched as the safety net and `/compact` still works.
 *
 * Silent on success — the footer's context figure is the signal. Threshold is
 * max(100k, 10% of the window), capped at 80% of it: 100k on the 1M models and
 * on anything down to 128k, and 80% of a window smaller than that. The cap
 * exists because a floor above the window would compact on *every* settle,
 * paying for a summary of a context that was never large.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/** Floor: never compact below this many tokens. */
const MIN_THRESHOLD = 100_000;

/** Ceiling as a fraction of the window, for models smaller than 1M. */
const WINDOW_FRACTION = 0.1;

/** A threshold above this share of the window would fire on every settle. */
const MAX_WINDOW_SHARE = 0.8;

export default function (pi: ExtensionAPI) {
	pi.on("agent_settled", (event, ctx) => {
		try {
			// Escape: the user is steering, not stopping. Don't spend a call.
			if (event.aborted) return;

			// A `-p` / json / rpc run exits right after this event, so compacting
			// there buys nothing and costs a summary request.
			if (ctx.mode !== "tui") return;

			// Belt and braces: the whole point is to never compact mid-task, so
			// let pi's own idleness flag enforce it rather than trusting the event.
			if (!ctx.isIdle()) return;

			const usage = ctx.getContextUsage();
			// `tokens` is null between a compaction and the next response.
			if (!usage || usage.tokens === null) return;

			const threshold = Math.min(
				Math.max(MIN_THRESHOLD, usage.contextWindow * WINDOW_FRACTION),
				usage.contextWindow * MAX_WINDOW_SHARE,
			);
			if (usage.tokens < threshold) return;

			// Async behind the scenes; onError is required to keep a failed
			// summary from surfacing as an unhandled rejection.
			ctx.compact({ onError: () => {} });
		} catch {
			// Never throw into the run.
		}
	});
}
