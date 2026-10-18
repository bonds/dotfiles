/**
 * Git Checkpoint — stash a recoverable code state at each turn.
 *
 * From pi's examples/extensions/git-checkpoint.ts. When a session is forked,
 * offers to restore the working tree to that point.
 *
 * `git stash create` only builds the commit object; it does not touch the
 * working tree or the stash list, so this is safe to run per turn. Outside a
 * git repo it exits non-zero and the turn is simply not checkpointed.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	const checkpoints = new Map<string, string>();
	let currentEntryId: string | undefined;

	pi.on("tool_result", async (_event, ctx) => {
		const leaf = ctx.sessionManager.getLeafEntry();
		if (leaf) currentEntryId = leaf.id;
	});

	pi.on("turn_start", async () => {
		const { stdout, code } = await pi.exec("git", ["stash", "create"]);
		const ref = code === 0 ? stdout.trim() : "";
		if (ref && currentEntryId) {
			checkpoints.set(currentEntryId, ref);
		}
	});

	pi.on("session_before_fork", async (event, ctx) => {
		const ref = checkpoints.get(event.entryId);
		if (!ref) return;

		if (!ctx.hasUI) return;

		const choice = await ctx.ui.select("Restore code state?", [
			"Yes, restore code to that point",
			"No, keep current code",
		]);

		if (choice?.startsWith("Yes")) {
			await pi.exec("git", ["stash", "apply", ref]);
			ctx.ui.notify("Code restored to checkpoint", "info");
		}
	});

	pi.on("agent_settled", async () => {
		checkpoints.clear();
	});
}
