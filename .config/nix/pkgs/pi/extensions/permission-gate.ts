/**
 * Permission Gate — confirm dangerous shell commands.
 *
 * Based on pi's examples/extensions/permission-gate.ts, extended with the
 * commands this setup actually uses:
 *   - `doas` (sophrosyne's privilege escalation; `sudo` is rare here)
 *   - forced pushes (AGENTS.md forbids them on any remote)
 *   - system activation (`nr`, `nixos-rebuild switch`, …): builds are fine,
 *     but Scott runs the activating rebuild himself, so an agent must never
 *     reach it.
 *
 * Non-interactive runs block by default rather than silently proceeding.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const dangerous: { pattern: RegExp; unless?: RegExp; why: string }[] = [
	{ pattern: /\brm\s+(-[a-z]*r[a-z]*|--recursive|--no-preserve-root)/i, why: "recursive delete" },
	{
		pattern: /\b(sudo|doas)\b/i,
		// The noPass doas commands agents use routinely (see AGENTS.md → doas).
		unless: /\bdoas\s+\S*\/?(systemctl|journalctl)\b/,
		why: "privilege escalation",
	},
	{ pattern: /\b(chmod|chown)\b.*\b777\b/i, why: "world-writable permissions" },
	{ pattern: /\bgit\s+push\b.*(\s-f\b|--force)/i, why: "forced push (forbidden on every remote here)" },
	{ pattern: /\b(mkfs(\.\w+)?|dd\s+if=|diskutil\s+(erase|reformat))\b/i, why: "destructive disk operation" },
	{
		// `nr` only at command position (start, after a separator, or inside
		// quotes, as in `fish -c 'nr'`), so `echo nr` and `grep nr` still run.
		pattern: /(^|[;&|('"`])nr(?=$|[\s;&|)'"`])/i,
		why: "system activation (Scott runs `nr` himself; build-only verification is allowed)",
	},
	{
		// The switch forms, with an optional absolute path (doas rules match on
		// the full path, e.g. /run/current-system/sw/bin/nixos-rebuild).
		pattern:
			/(^|[\s;&|('"`])(\S*\/)?((nixos|darwin)-rebuild\s+switch|nh\s+(os|darwin)\s+switch|home-manager\s+switch)(?=$|[\s;&|)'"`])/i,
		why: "system activation (Scott runs the activating rebuild; `nh darwin build` is fine)",
	},
];

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return undefined;

		const command = event.input.command as string;
		const hit = dangerous.find(
			({ pattern, unless }) => pattern.test(command) && !unless?.test(command),
		);
		if (!hit) return undefined;

		if (!ctx.hasUI) {
			return {
				block: true,
				reason: `Blocked (${hit.why}) with no UI to confirm: ${command}`,
			};
		}

		const choice = await ctx.ui.select(
			`⚠️ Dangerous command (${hit.why}):\n\n  ${command}\n\nAllow?`,
			["Yes", "No"],
		);

		if (choice !== "Yes") {
			return { block: true, reason: `Blocked by user: ${hit.why}` };
		}

		return undefined;
	});
}
