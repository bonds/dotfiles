/**
 * Session recall — search past pi sessions from inside a session.
 *
 * Sessions are JSONL files under `<agent-dir>/sessions/<project>/`. They hold
 * every prompt, tool call and tool result, so the answer to "how did we fix
 * this last time?" is usually already on disk — the agent just cannot see it.
 * This tool makes that corpus searchable, which is the payoff of the capture
 * loop: without it, a lesson that was never promoted to a skill is lost the
 * moment its session scrolls out of context.
 *
 * Registered with `codemode` exposure: it stays out of the declared tool list
 * (the model reaches it from a codemode script, where it lists it) and costs
 * nothing per request.
 *
 * Read-only. Bounded output: the model gets snippets plus the session file
 * path, and can `read` that file for the full history.
 */

import { readdir, readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const AGENT_DIR = process.env.PI_CODING_AGENT_DIR ?? join(homedir(), ".pi", "agent");
const SESSIONS = join(AGENT_DIR, "sessions");
const MAX_OUTPUT = 4000;
const MAX_SEARCH_CHARS = 16_000;
const MAX_SNIPPET = 240;

interface Hit {
	file: string;
	sessionId: string;
	name?: string;
	cwd?: string;
	date: string;
	role: string;
	text: string;
	score: number;
}

function textOfContent(content: unknown): string {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	const parts: string[] = [];
	for (const block of content) {
		if (!block || typeof block !== "object") continue;
		const b = block as Record<string, unknown>;
		if (b.type === "text" && typeof b.text === "string") parts.push(b.text);
		else if (b.type === "thinking" && typeof b.thinking === "string") parts.push(b.thinking);
		else if (b.type === "toolCall" && typeof b.name === "string") {
			parts.push(`${b.name}(${JSON.stringify(b.arguments ?? {})})`);
		}
	}
	return parts.join("\n");
}

function snippet(text: string, terms: string[]): string {
	const flat = text.replace(/\s+/g, " ").trim();
	const lower = flat.toLowerCase();
	let at = -1;
	for (const term of terms) {
		const found = lower.indexOf(term);
		if (found >= 0 && (at < 0 || found < at)) at = found;
	}
	if (at < 0) return flat.slice(0, MAX_SNIPPET);
	const start = Math.max(0, at - 80);
	return `${start > 0 ? "…" : ""}${flat.slice(start, start + MAX_SNIPPET)}`;
}

/** Filenames start with an ISO timestamp: 2026-10-18T18-46-36-093Z_<id>.jsonl */
function fileDate(name: string): number {
	const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})/.exec(name);
	if (!match) return 0;
	const [, y, mo, d, h, mi, s] = match;
	return Date.UTC(Number(y), Number(mo) - 1, Number(d), Number(h), Number(mi), Number(s));
}

async function sessionFiles(sinceMs: number): Promise<string[]> {
	const files: string[] = [];
	let projects: string[];
	try {
		projects = await readdir(SESSIONS);
	} catch {
		return files;
	}
	for (const project of projects) {
		const dir = join(SESSIONS, project);
		let names: string[];
		try {
			names = await readdir(dir);
		} catch {
			continue;
		}
		for (const name of names) {
			if (!name.endsWith(".jsonl")) continue;
			if (fileDate(name) < sinceMs) continue;
			files.push(join(dir, name));
		}
	}
	// Newest first: a recent session is the likelier hit.
	return files.sort((a, b) => fileDate(basename(b)) - fileDate(a));
}

async function search(file: string, terms: string[]): Promise<Hit[]> {
	const hits: Hit[] = [];
	let raw: string;
	try {
		raw = await readFile(file, "utf8");
	} catch {
		return hits;
	}

	const header = { id: basename(file).replace(/^[^_]*_/, "").replace(/\.jsonl$/, ""), name: undefined as string | undefined, cwd: undefined as string | undefined };
	for (const line of raw.split("\n")) {
		if (line.length === 0) continue;
		let entry: Record<string, unknown>;
		try {
			entry = JSON.parse(line) as Record<string, unknown>;
		} catch {
			continue;
		}

		if (entry.type === "session") {
			if (typeof entry.id === "string") header.id = entry.id;
			if (typeof entry.cwd === "string") header.cwd = entry.cwd;
			continue;
		}
		if (entry.type === "session_name" && typeof entry.name === "string") {
			header.name = entry.name;
			continue;
		}
		if (entry.type !== "message" || !entry.message) continue;

		const message = entry.message as Record<string, unknown>;
		const role = typeof message.role === "string" ? message.role : "?";
		if (role === "system") continue; // the prompt itself matches everything
		const text = textOfContent(message.content).slice(0, MAX_SEARCH_CHARS);
		if (text.length === 0) continue;

		const lower = text.toLowerCase();
		let matched = 0;
		for (const term of terms) if (lower.includes(term)) matched++;
		if (matched === 0) continue;

		hits.push({
			file,
			sessionId: header.id,
			name: header.name,
			cwd: header.cwd,
			date: typeof entry.timestamp === "string" ? entry.timestamp.slice(0, 16).replace("T", " ") : "?",
			role,
			text: snippet(text, terms),
			score: matched,
		});
	}
	return hits;
}

const RecallParams = Type.Object({
	query: Type.String({
		description: "Words to look for. All words must appear in the same entry; paths and flags work too.",
	}),
	limit: Type.Optional(Type.Number({ description: "Maximum hits to return (default 6, max 20)." })),
	days: Type.Optional(Type.Number({ description: "Only search sessions from the last N days (default 30)." })),
	session: Type.Optional(
		Type.String({ description: "Only search sessions whose file path contains this text (project name or session id)." }),
	),
});

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "recall",
		label: "Recall",
		description:
			"Search past pi sessions for something you or the user already worked out: an error message, a command, a file path, a decision. Use it before re-deriving an answer from scratch.",
		promptSnippet: "Search past sessions for earlier work on the same problem",
		parameters: RecallParams,
		exposure: "codemode",
		annotations: { readOnlyHint: true, idempotentHint: true, openWorldHint: false },
		async execute(_toolCallId, params) {
			const query = String(params.query ?? "").trim();
			const terms = query.toLowerCase().split(/\s+/).filter((term) => term.length > 0);
			if (terms.length === 0) {
				throw new Error("recall: query is empty");
			}

			const limit = Math.min(Math.max(Number(params.limit ?? 6) || 6, 1), 20);
			const days = Math.max(Number(params.days ?? 30) || 30, 1);
			const since = Date.now() - days * 24 * 60 * 60 * 1000;

			const files = (await sessionFiles(since)).filter(
				(file) => !params.session || file.includes(String(params.session)),
			);

			const all: Hit[] = [];
			for (const file of files) {
				const hits = await search(file, terms);
				all.push(...hits);
			}

			// Every-term matches first, then partial; newest first within each.
			all.sort((a, b) => b.score - a.score);
			const chosen = all.slice(0, limit);

			if (chosen.length === 0) {
				return {
					content: [
						{
							type: "text",
							text: `No sessions in the last ${days} days match "${query}" (${files.length} searched). Try fewer or shorter words, a larger days value, or no session filter.`,
						},
					],
					details: undefined,
				};
			}

			const lines: string[] = [
				`${chosen.length} hit(s) for "${query}" across ${files.length} session(s) from the last ${days} days.`,
				"",
			];
			for (const [index, hit] of chosen.entries()) {
				const where = hit.name ? `${hit.name} (${hit.sessionId.slice(0, 8)})` : hit.sessionId.slice(0, 8);
				lines.push(`${index + 1}. ${hit.date} · ${hit.role} · ${where}${hit.cwd ? ` · ${hit.cwd}` : ""}`);
				lines.push(`   ${hit.text}`);
				lines.push(`   file: ${hit.file}`);
			}

			let text = lines.join("\n");
			if (text.length > MAX_OUTPUT) text = `${text.slice(0, MAX_OUTPUT)}\n…truncated; narrow the query for more`;
			return { content: [{ type: "text", text }], details: undefined };
		},
	});
}
