/**
 * Learnings capture — write down surprises at the moment they happen.
 *
 * The failure mode this fixes: the moment a lesson exists (a tool call just
 * failed in a non-obvious way) is the moment the agent is least likely to
 * record it, because it is mid-debugging and distracted. `~/AGENTS.md` says
 * "log surprises next to the code" and `/learn` exists, but nothing catches
 * the surprise, so those instructions are aspirational.
 *
 * This extension appends a one-line candidate to `<agent-dir>/inbox.md` when a
 * tool call fails. `/distill` then clusters the inbox and promotes each item
 * up the ladder (AGENTS.md line -> skill -> hook -> automation).
 *
 * Deliberately cheap and dumb:
 *   - no model calls, no network, no judgment
 *   - capture immediately for "deliberate" failures (blocked by policy,
 *     permission denied, missing command); capture everything else only on
 *     its SECOND occurrence in a session, which filters out the noise of an
 *     agent probing paths that were never there
 *   - one line per distinct signature: the inbox is a set of unresolved
 *     lessons, not a log, so re-seeing the same error does not grow it
 *   - rotates at 64 KiB so a forgotten inbox cannot grow without bound
 */

import { appendFile, mkdir, readFile, rename, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const AGENT_DIR = process.env.PI_CODING_AGENT_DIR ?? join(homedir(), ".pi", "agent");
const INBOX = join(AGENT_DIR, "inbox.md");
const ROTATE_BYTES = 64 * 1024;
const MAX_SIGNATURE = 140;

const HEADER = `# Learnings inbox

Candidates written by the \`learnings-capture\` extension when a tool call
failed. Each line is one distinct failure signature in one session.

Run \`/distill\` to cluster these and promote them (AGENTS.md -> skill -> hook),
then empty this file. Do not edit by hand: delete lines instead.
`;

/**
 * Failures worth recording on first sight: they are decisions, not accidents.
 * A blocked write, a denied sudo, or a missing binary will recur in exactly
 * the same shape until something above rung 1 of the ladder changes.
 */
const IMMEDIATE = [
	/refusing to modify/i,
	/not approved/i,
	/permission denied/i,
	/operation not permitted/i,
	/publickey/i,
	/command not found/i,
	/cannot find module/i,
	/is not a function/i,
	/unknown option/i,
	/invalid option/i,
];

interface Failure {
	/** Human-readable one-liner, kept close to the original wording. */
	display: string;
	/** Normalized text used for dedupe, lowercased. */
	key: string;
}

function textOf(content: unknown): string {
	if (!Array.isArray(content)) return "";
	return content
		.map((block) => {
			if (block && typeof block === "object" && "type" in block) {
				const b = block as { type: string; text?: string };
				if (b.type === "text" && typeof b.text === "string") return b.text;
			}
			return "";
		})
		.join("\n");
}

/** Lines that carry no signal on their own: bash's own exit-code banner. */
const NOISE = [/^exit code \d+$/i, /^exit status \d+$/i, /^command exited with/i];

/** A line that names the failure, rather than echoing a path or a usage dump. */
const SIGNAL = /error|denied|not found|refus|blocked|fail|invalid|unknown|cannot|unable|no such/i;

function describe(raw: string): Failure {
	const lines = raw
		.replace(/\x1b\[[0-9;]*m/g, "") // ANSI colors
		.split("\n")
		.map((line) => line.trim())
		.filter((line) => line.length > 0 && !NOISE.some((pattern) => pattern.test(line)));

	// Prefer a line that names the failure; fall back to whatever came first.
	const chosen = lines.find((line) => SIGNAL.test(line)) ?? lines[0];
	const display = (chosen ?? "(no output)").slice(0, MAX_SIGNATURE);
	const key = display
		.replace(/(?:\/[\w.@+-]+){2,}/g, "<path>") // absolute paths
		.replace(/\b[0-9a-f]{8}-[0-9a-f-]{20,}\b/gi, "<id>")
		.replace(/\b0x[0-9a-f]+\b/gi, "<addr>")
		.replace(/\s+/g, " ")
		.toLowerCase();
	return { display, key };
}

/** FNV-1a; only used to tag a line so later sessions can dedupe against it. */
function hash(input: string): string {
	let h = 0x811c9dc5;
	for (let i = 0; i < input.length; i++) {
		h ^= input.charCodeAt(i);
		h = Math.imul(h, 0x01000193) >>> 0;
	}
	return h.toString(16).padStart(8, "0");
}

function stamp(): string {
	const now = new Date();
	const pad = (n: number) => String(n).padStart(2, "0");
	return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}`;
}

function shortPath(path: string): string {
	const home = homedir();
	return path.startsWith(home) ? `~${path.slice(home.length)}` : path;
}

/** Read the inbox, rotating it first if it has grown too large. */
async function readInbox(): Promise<string> {
	try {
		const info = await stat(INBOX);
		if (info.size > ROTATE_BYTES) {
			await rename(INBOX, `${INBOX}.1`).catch(() => undefined);
			return "";
		}
		return await readFile(INBOX, "utf8");
	} catch {
		return "";
	}
}

async function record(
	failure: Failure,
	toolName: string,
	count: number,
	ctx: ExtensionContext,
): Promise<void> {
	const tag = `<!--k:${hash(failure.key)}-->`;
	const existing = await readInbox();
	if (existing.includes(tag)) return; // already an unresolved candidate

	await mkdir(AGENT_DIR, { recursive: true });
	const sessionId = ctx.sessionManager.getSessionId();
	const session = sessionId ? sessionId.slice(0, 8) : "unknown";
	const times = count > 1 ? ` x${count}` : "";
	const line = `- [${stamp()}] \`${toolName}\`${times} — ${failure.display} — ${shortPath(ctx.cwd)} — session ${session} ${tag}\n`;

	// Append only the new line: `existing` is read to dedupe, not to rewrite.
	const separator = existing.length > 0 ? (existing.endsWith("\n") ? "" : "\n") : `${HEADER}\n`;
	await appendFile(INBOX, separator + line, "utf8");

	if (ctx.hasUI) {
		ctx.ui.notify(`inbox: ${failure.display}`, "info");
	}
}

export default function (pi: ExtensionAPI) {
	// Signatures seen in THIS session, so the two-strike rule is session-local.
	const counts = new Map<string, number>();

	pi.on("session_start", async () => {
		counts.clear();
	});

	pi.on("tool_result", async (event, ctx) => {
		if (!event.isError) return;

		const failure = describe(textOf(event.content));
		if (failure.key.length === 0) return;

		const seen = (counts.get(failure.key) ?? 0) + 1;
		counts.set(failure.key, seen);

		const deliberate = IMMEDIATE.some((pattern) => pattern.test(failure.display));
		if (!deliberate && seen < 2) return;

		// Never let bookkeeping break the run.
		try {
			await record(failure, event.toolName, seen, ctx);
		} catch {
			return;
		}
	});
}
