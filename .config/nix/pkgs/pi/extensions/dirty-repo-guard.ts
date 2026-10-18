/**
 * Dirty Repo Guard — confirm before switching or forking with uncommitted work.
 *
 * From pi's examples/extensions/dirty-repo-guard.ts. Pairs with the AGENTS.md
 * rule "after each batch of changes, commit and push": switching context with
 * a dirty tree is usually a mistake, so ask first.
 *
 * In $HOME the dotfiles bare repo has no working `.git`, so `git status`
 * fails and the guard allows the action — that is expected.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

async function checkDirtyRepo(
	pi: ExtensionAPI,
	ctx: ExtensionContext,
	action: string,
): Promise<{ cancel: boolean } | undefined> {
	const { stdout, code } = await pi.exec("git", ["status", "--porcelain"]);

	// Not a git repo (or git failed): nothing to guard.
	if (code !== 0) return;

	const changed = stdout.trim().split("\n").filter(Boolean);
	if (changed.length === 0) return;

	if (!ctx.hasUI) return { cancel: true };

	const choice = await ctx.ui.select(
		`${changed.length} uncommitted file(s). ${action} anyway?`,
		["Yes, proceed anyway", "No, let me commit first"],
	);

	if (choice !== "Yes, proceed anyway") {
		ctx.ui.notify("Commit your changes first", "warning");
		return { cancel: true };
	}
}

export default function (pi: ExtensionAPI) {
	pi.on("session_before_switch", async (event, ctx) => {
		const action = event.reason === "new" ? "Start a new session" : "Switch session";
		return checkDirtyRepo(pi, ctx, action);
	});

	pi.on("session_before_fork", async (_event, ctx) => {
		return checkDirtyRepo(pi, ctx, "Fork");
	});
}
