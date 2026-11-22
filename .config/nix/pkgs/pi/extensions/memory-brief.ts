/**
 * Memory brief — put what this repository already knows into the prompt.
 *
 * The failure mode this fixes: every session starts from zero. `~/AGENTS.md`
 * says "read `DECISIONS.md` before proposing to change one" and "log surprises
 * next to the code", but nothing tells the model that 44 learnings already
 * exist for this repo, what they are about, or that 28 inbox candidates are
 * waiting to be distilled. So it re-derives, or re-litigates, what the last
 * forty sessions already settled.
 *
 * The fix is one `mem brief` call per session, injected as a `<memory>` prompt
 * section. Pi diffs prompt sections and patches only what changed, so an
 * unchanged brief costs nothing after the first run — and `mem brief` is local
 * and deterministic (counts and titles off disk, no network, no archive scan),
 * which is what makes it safe to run on every session start.
 *
 * Deliberately a snapshot: the brief is taken when the session starts and does
 * not follow captures made during it. A brief that shifted mid-session would
 * rewrite the system prompt for no new information.
 *
 * The footer shows the inbox backlog (`ctx.ui.setStatus`) so a growing inbox is
 * visible rather than a surprise at the next distill.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

/** `mem` is on PATH via home-manager; MEM_BIN overrides it for a checkout. */
const MEM_BIN = process.env.MEM_BIN ?? "mem";
/** Generous for a command that reads four small files; a hang must not block the run. */
const TIMEOUT_MS = 2500;
const STATUS_KEY = "memory";

interface Brief {
	/** The working directory this brief describes; a stale one is not reused. */
	cwd: string;
	/** The text injected into the prompt, already budgeted by `mem`. */
	text: string;
	inbox: number;
	/** Candidates that look like they contradict a rule that already exists. */
	contradicting: number;
	repo: string | null;
}

function parse(raw: string, cwd: string): Brief | undefined {
	const data = JSON.parse(raw) as {
		text?: unknown;
		repo?: unknown;
		inbox?: { count?: unknown };
		distill?: { contradicting?: unknown };
	};
	if (typeof data.text !== "string" || data.text.trim() === "") return undefined;
	return {
		cwd,
		text: data.text.trim(),
		inbox: typeof data.inbox?.count === "number" ? data.inbox.count : 0,
		contradicting:
			typeof data.distill?.contradicting === "number" ? data.distill.contradicting : 0,
		repo: typeof data.repo === "string" ? data.repo : null,
	};
}

/**
 * The footer badge. "28" alone reads as somebody else's problem; the count that
 * makes a backlog actionable is the one the audit already computed, so show it
 * when it is not zero.
 */
function statusOf(brief: Brief | undefined): string | undefined {
	if (!brief || brief.inbox === 0) return undefined;
	const clash = brief.contradicting > 0 ? ` · ${brief.contradicting} clash` : "";
	return `inbox ${brief.inbox}${clash}`;
}

export default function (pi: ExtensionAPI) {
	let brief: Brief | undefined;
	let pending: Promise<Brief | undefined> | undefined;
	let pendingFor: string | undefined;

	/**
	 * The brief for this working directory, loading it at most once. Never
	 * throws: a missing `mem` or a slow disk must not break a run, it just
	 * means no injected context.
	 */
	const ensure = async (ctx: ExtensionContext): Promise<Brief | undefined> => {
		if (brief && brief.cwd === ctx.cwd) return brief;
		if (!pending || pendingFor !== ctx.cwd) {
			pendingFor = ctx.cwd;
			pending = (async () => {
				try {
					const result = await pi.exec(
						MEM_BIN,
						["brief", "--cwd", ctx.cwd, "--json"],
						{ timeout: TIMEOUT_MS, signal: ctx.signal },
					);
					if (result.code !== 0) return undefined;
					return parse(result.stdout, ctx.cwd);
				} catch {
					return undefined;
				}
			})().then((loaded) => {
				if (loaded) brief = loaded;
				if (ctx.hasUI) ctx.ui.setStatus(STATUS_KEY, statusOf(loaded));
				return loaded;
			});
		}
		return pending;
	};

	pi.on("session_start", async (_event, ctx) => {
		// A new session gets a fresh snapshot: captures from the last one may
		// have changed the inbox count.
		brief = undefined;
		pending = undefined;
		pendingFor = undefined;
		void ensure(ctx);
	});

	pi.on("before_agent_start", async (event, ctx) => {
		const loaded = await ensure(ctx);
		if (!loaded) return;
		// Mutating the collection is the documented way to add a section: pi
		// renders it as <memory>…</memory> and patches only what changed.
		event.systemPromptOptions.sections.memory = loaded.text;
	});
}
