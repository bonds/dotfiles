/**
 * Protected Paths — block write/edit to secrets and generated trees.
 *
 * Based on pi's examples/extensions/protected-paths.ts, tightened for this
 * dotfiles setup: the repo is public and the machine holds age-encrypted
 * secrets (passage), agenix-decrypted runtime files, and SSH keys that no
 * agent should ever rewrite.
 *
 * Only `write` and `edit` are gated; reads stay unrestricted.
 */

import { resolve } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const protectedPatterns: { pattern: RegExp; why: string }[] = [
	{ pattern: /(^|\/)\.env(\.[^/]*)?$/, why: "environment secrets" },
	{ pattern: /(^|\/)\.git(\/|$)/, why: "git internals (use git)" },
	{ pattern: /(^|\/)node_modules(\/|$)/, why: "generated dependencies" },
	{ pattern: /^\/run\/agenix(\/|$)/, why: "agenix-decrypted secrets" },
	{ pattern: /(^|\/)secrets(\/|$)/, why: "age-encrypted secrets" },
	{ pattern: /(^|\/)\.ssh(\/|$)/, why: "SSH keys and agent config" },
	{ pattern: /(^|\/)\.config\/passage(\/|$)/, why: "password store" },
	{ pattern: /(^|\/)authorized_keys$/, why: "SSH authorization" },
	{ pattern: /(^|\/)\.pi\/agent\/auth\.json$/, why: "saved API credentials" },
];

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "write" && event.toolName !== "edit") {
			return undefined;
		}

		const raw = event.input.path as string | undefined;
		if (!raw) return undefined;

		// Tools receive either an absolute path or one relative to the cwd.
		const absolute = raw.startsWith("/") ? raw : resolve(ctx.cwd, raw);
		const candidates = [raw.replace(/\/+$/, ""), absolute];

		for (const candidate of candidates) {
			for (const { pattern, why } of protectedPatterns) {
				if (!pattern.test(candidate)) continue;

				const reason = `Refusing to modify ${absolute}: ${why}`;
				if (ctx.hasUI) ctx.ui.notify(reason, "warning");
				return { block: true, reason };
			}
		}

		return undefined;
	});
}
