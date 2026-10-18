/**
 * Corrections capture — record the lessons that produce no failed tool call.
 *
 * `learnings-capture.ts` only sees tool errors. But the most valuable lessons
 * arrive as a sentence from the user: "no, use `config push`, not `git push`",
 * or "from now on, never run the rebuild yourself". Nothing fails, so nothing
 * captures it, and it survives only if the agent remembers to write it down —
 * the same "remember to remember" failure the inbox exists to remove.
 *
 * This extension listens on pi's `input` event, which fires before the turn
 * with the raw text and its source, and appends a line to the same inbox when
 * the text looks like a correction or a policy statement. The line carries the
 * preceding assistant action, because "no" is worthless to `/distill` while
 * "no" after `git push origin main` is a rung-3 lesson.
 *
 * Cheap and dumb, like its sibling: no model calls, no judgment beyond a
 * phrase list, and a false positive costs one line that `/distill` deletes.
 *
 * Two deliberate biases:
 *   - Recall over precision. A missed "from now on, never…" costs a repeated
 *     mistake; a spurious line costs nothing.
 *   - No notification. A correction is not news to the person who typed it.
 *
 * The inbox helpers are duplicated from learnings-capture.ts on purpose: each
 * extension stays self-contained, so breaking one cannot take out the other.
 */

import { appendFile, mkdir, readFile, rename, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const AGENT_DIR = process.env.PI_CODING_AGENT_DIR ?? join(homedir(), ".pi", "agent");
const INBOX = join(AGENT_DIR, "inbox.md");
const ROTATE_BYTES = 64 * 1024;
const MAX_QUOTE = 200;
const MAX_CONTEXT = 100;

/** Longest message still treated as a terse instruction rather than prose. */
const SHORT_MESSAGE = 240;
/** Past this, the text is a paste, not a correction. */
const MAX_MESSAGE = 2000;

const HEADER = `# Learnings inbox

Candidates written by the \`learnings-capture\` and \`corrections-capture\`
extensions when a tool call failed, or when the user corrected the agent or
stated a rule.

Run \`/distill\` to cluster these and promote them (AGENTS.md -> skill -> hook),
then empty this file. Do not edit by hand: delete lines instead.
`;

/** "Don't do that" — usually an explicit rejection of what just happened. */
const CORRECTION = [
	/^(no|nope|nah|stop)\b/i,
	/\bdon'?t\b/i,
	/\bdo not\b/i,
	/\bnot that\b/i,
	/\bI said\b/i,
	/\bI told you\b/i,
	/\bthat'?s (wrong|not right|incorrect)\b/i,
	/\bwhy did you\b/i,
	/\bshould (be|have)\b/i,
	/\binstead\b/i,
];

/** "Always / never / prefer" — only trusted in a short, instruction-shaped message. */
const WEAK_POLICY = [/\balways\b/i, /\bnever\b/i, /\bprefer\b/i];

/** Unambiguous policy markers: captured regardless of message length. */
const EXPLICIT_POLICY = [/\bfrom now on\b/i, /\bgoing forward\b/i, /\bnext time\b/i];

interface Quote {
	kind: "correction" | "policy";
	text: string;
}

/** The sentence containing the match, not the whole message. */
function sentenceAround(text: string, patterns: RegExp[]): string {
	const sentences = text.split(/(?<=[.!?])\s+/);
	const hit = sentences.find((sentence) => patterns.some((pattern) => pattern.test(sentence)));
	const chosen = (hit ?? text).replace(/\s+/g, " ").trim();
	return chosen.length > MAX_QUOTE ? `${chosen.slice(0, MAX_QUOTE)}…` : chosen;
}

function classify(text: string): Quote | undefined {
	// Slash commands and long pastes are not corrections; `/distill` itself is
	// full of "always" and "never" and must not capture itself.
	if (text.startsWith("/")) return undefined;
	if (text.length > MAX_MESSAGE) return undefined;
	if (text.length > 600 && text.includes("```")) return undefined;

	if (EXPLICIT_POLICY.some((pattern) => pattern.test(text))) {
		return { kind: "policy", text: sentenceAround(text, EXPLICIT_POLICY) };
	}
	if (text.length <= SHORT_MESSAGE && WEAK_POLICY.some((pattern) => pattern.test(text))) {
		return { kind: "policy", text: sentenceAround(text, WEAK_POLICY) };
	}
	if (CORRECTION.some((pattern) => pattern.test(text))) {
		return { kind: "correction", text: sentenceAround(text, CORRECTION) };
	}
	return undefined;
}

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

/** What the correction was correcting: the last tool call or assistant text. */
function lastAction(ctx: ExtensionContext): string {
	const branch = ctx.sessionManager.getBranch();
	for (let i = branch.length - 1; i >= 0; i--) {
		const entry = branch[i] as { type?: string; message?: { role?: string; content?: unknown } };
		if (entry.type !== "message" || entry.message?.role !== "assistant") continue;

		const content = Array.isArray(entry.message.content) ? entry.message.content : [];
		const calls = content.filter(
			(block): block is { type: string; name: string; arguments?: Record<string, unknown> } =>
				typeof block === "object" && block !== null && (block as { type?: string }).type === "toolCall",
		);
		if (calls.length > 0) {
			const call = calls[calls.length - 1];
			const args = call.arguments ?? {};
			const detail =
				typeof args.command === "string"
					? args.command
					: typeof args.path === "string"
						? args.path
						: JSON.stringify(args);
			const flat = String(detail).replace(/\s+/g, " ").trim();
			const short = flat.length > MAX_CONTEXT ? `${flat.slice(0, MAX_CONTEXT)}…` : flat;
			return `after \`${call.name}\` \`${short}\``;
		}

		const text = content
			.filter((block) => typeof block === "object" && block !== null && (block as { type?: string }).type === "text")
			.map((block) => String((block as { text?: string }).text ?? ""))
			.join(" ")
			.replace(/\s+/g, " ")
			.trim();
		if (text.length > 0) {
			const short = text.length > MAX_CONTEXT ? `${text.slice(0, MAX_CONTEXT)}…` : text;
			return `after "${short}"`;
		}
	}
	return "after the previous turn";
}

async function record(quote: Quote, ctx: ExtensionContext): Promise<void> {
	const key = quote.text.toLowerCase().replace(/\s+/g, " ");
	const tag = `<!--c:${hash(key)}-->`;

	const existing = await readInbox();
	if (existing.includes(tag)) return; // already an unresolved candidate

	await mkdir(AGENT_DIR, { recursive: true });
	const sessionId = ctx.sessionManager.getSessionId();
	const session = sessionId ? sessionId.slice(0, 8) : "unknown";
	const line = `- [${stamp()}] ${quote.kind} — "${quote.text}" — ${lastAction(ctx)} — ${shortPath(ctx.cwd)} — session ${session} ${tag}\n`;

	// Append only the new line: `existing` is read to dedupe, not to rewrite.
	const separator = existing.length > 0 ? (existing.endsWith("\n") ? "" : "\n") : `${HEADER}\n`;
	await appendFile(INBOX, separator + line, "utf8");
}

export default function (pi: ExtensionAPI) {
	pi.on("input", async (event, ctx) => {
		// Only extension-injected messages are excluded: those are the harness
		// talking (queued follow-ups, /distill expansions), not the user.
		if (event.source === "extension") return { action: "continue" };

		const text = event.text.trim();
		const quote = classify(text);
		if (!quote) return { action: "continue" };

		// Never let bookkeeping break the turn.
		try {
			await record(quote, ctx);
		} catch {
			return { action: "continue" };
		}
		return { action: "continue" };
	});
}
