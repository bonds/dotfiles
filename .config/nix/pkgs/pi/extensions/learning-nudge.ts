/**
 * Learning nudge — the one moment a domain lesson is born, noticed.
 *
 * `learnings-capture` records failures into the inbox, and the `learning` tool
 * writes `<repo>/docs/learnings/`, but nothing connects the second to the
 * situation that produces it: a tool call failed, the agent tried something
 * different, and the retry worked. That pair *is* the lesson — symptom, cause,
 * fix — and it is the moment the agent is least likely to write it down, being
 * mid-task and relieved.
 *
 * So this extension watches for exactly that shape and says one line about it,
 * once per session:
 *   - a tool call fails, then the same tool succeeds with **different**
 *     arguments, within RETRY_WINDOW tool calls
 *   - the failure is not a negative search result (`rg`/`grep` exit 1 means
 *     "nothing matched", which is an answer, not a trap)
 *   - the working directory is inside a git repository, since that is where a
 *     learnings entry can live
 *   - nothing has been written to `docs/learnings/` this session already
 *
 * No model call, no file writes: the nudge is a `display: false` custom message
 * appended at `turn_end`, so the model sees it on its next turn. It never
 * requests a continuation — a nudge must not cost a request, and the decision
 * to record the lesson stays the agent's (and the human's).
 */

import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const RETRY_WINDOW = 6;
const MAX_QUOTE = 160;

/** Tools whose "nothing found" exit is a result, not a failure. */
const SEARCH_TOOLS = new Set(["grep", "find", "rg", "fd", "ls", "glob"]);
const LEARNING_TOOLS = new Set(["learning", "record_learning"]);

interface Failure {
	toolName: string;
	args: string;
	message: string;
	/** What the successful retry printed, quoted at the moment it succeeded. */
	fix?: string;
	/** Tool calls seen since the failure, to bound "a retry" to the same moment. */
	age: number;
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

/** A stable signature for a call's arguments, so "different arguments" is decidable. */
function argsKey(input: unknown): string {
	try {
		return JSON.stringify(input ?? {});
	} catch {
		return "";
	}
}

/** The line worth quoting: the first that names a cause rather than echoing output. */
function quote(raw: string): string {
	const lines = raw
		.replace(/\x1b\[[0-9;]*m/g, "")
		.split("\n")
		.map((line) => line.trim())
		.filter((line) => line.length > 0 && !/^exit (code|status) \d+$/i.test(line));
	const named = lines.find((line) => /^(?!usage:)[a-z][\w.+-]*:\s/i.test(line));
	return (named ?? lines[0] ?? "").slice(0, MAX_QUOTE);
}

function repoRoot(from: string): string | undefined {
	let dir = from;
	for (;;) {
		if (existsSync(join(dir, ".git"))) return dir;
		const parent = dirname(dir);
		if (parent === dir) return undefined;
		dir = parent;
	}
}

export default function (pi: ExtensionAPI) {
	let failure: Failure | undefined;
	let nudged = false;
	let wroteLearning = false;
	let calls = 0;

	pi.on("session_start", async () => {
		failure = undefined;
		nudged = false;
		wroteLearning = false;
		calls = 0;
	});

	pi.on("tool_result", async (event) => {
		calls += 1;
		if (event.isError) {
			if (SEARCH_TOOLS.has(event.toolName)) return;
			const message = quote(textOf(event.content));
			if (!message) return;
			failure = {
				toolName: event.toolName,
				args: argsKey(event.input),
				message,
				age: calls,
			};
			return;
		}

		if (LEARNING_TOOLS.has(event.toolName)) {
			wroteLearning = true;
			return;
		}
		// A success only completes a pair when it is the same tool, with
		// different arguments, close enough to be the retry.
		if (!failure || nudged) return;
		if (failure.toolName !== event.toolName) return;
		if (argsKey(event.input) === failure.args) return;
		if (calls - failure.age > RETRY_WINDOW) {
			failure = undefined;
			return;
		}
		failure = { ...failure, fix: quote(textOf(event.content)), age: calls };
	});

	pi.on("turn_end", async (event, ctx) => {
		// `fix` is only set by a successful retry: without it there is no pair,
		// and a nudge that claims "then succeeded" over a failure that failed
		// again is worse than silence — the model rightly distrusts it.
		if (!failure || !failure.fix || nudged || wroteLearning) return;
		// Same tool, changed arguments, and it worked: the pair is the lesson.
		const fix = failure.fix;
		// The window was checked when the retry was recognised; a failure with
		// no `fix` never reaches here.
		if (!repoRoot(ctx.cwd)) return;

		nudged = true;
		const content = [
			`A \`${failure.toolName}\` call failed and then succeeded with different arguments.`,
			`  failed: ${failure.message}`,
			fix ? `  worked: ${fix}` : undefined,
			"If a future session in this repository would hit the same trap, record it with",
			"`learning` (symptom, cause, fix). Agent-conduct rules belong in the inbox instead",
			"(`mem inbox add`), which /distill drains.",
		]
			.filter(Boolean)
			.join("\n");

		return {
			entries: [
				...(event.entries ?? []),
				{
					type: "custom_message",
					customType: "learning-nudge",
					content,
					display: false,
				},
			],
		};
	});
}
