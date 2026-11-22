/**
 * Memory recall — bring up the earlier session that answered this, on the turns
 * where it would help.
 *
 * The `recall` tool already exists, but it only helps when the model remembers
 * it exists *and* that the answer is in the archive rather than in the code.
 * Questions like "how did we fix this last time?" are the ones where the model
 * has no idea it is repeating work.
 *
 * Three decisions keep this cheap:
 *   - **Gated by phrasing.** Only prompts that ask about the past fire a query;
 *     an ordinary "fix this test" never does. Recall is 1.3 s and a network
 *     round-trip, which is fine occasionally and unacceptable always.
 *   - **Started at `input`, awaited at `before_agent_start`.** The work runs
 *     while the prompt is still being expanded, and the run waits at most
 *     RECALL_TIMEOUT_MS for it. A miss injects nothing — the `recall` tool is
 *     still there, and a stalled turn is worse than a missed hint.
 *   - **`display: false`.** The hits go to the model as a custom message and do
 *     not fill the transcript; the footer status says `recall N` so the
 *     injection is visible without being noisy.
 *
 * Read-only, and every failure is silent: a missing `mem`, no index, no
 * embedder, or a timeout all mean "no injected context".
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const MEM_BIN = process.env.MEM_BIN ?? "mem";
/** Enough for `mem recall --mode semantic` (measured 1.3 s) plus a cold disk. */
const RECALL_TIMEOUT_MS = 2200;
/** The await cap in `before_agent_start`: never stall a run for a hint. */
const WAIT_MS = 1600;
const STATUS_KEY = "recall";
const MAX_HITS = 2;
/**
 * Characters per hit. The index stores at most `SNIPPET_CHARS` (240) of a unit,
 * so this is a ceiling, not a request: asking for more returns no more.
 */
const SNIPPET = 240;
const DAYS = 120;

/**
 * Prompts that ask about the past. Deliberately narrow: "before" and "again"
 * are ordinary words, "last time" and "have we" are questions about history.
 */
const GATE = [
	/\bhow did we\b/i,
	/\bwhat did we\b/i,
	/\bwhy did we\b/i,
	/\bwhere did we\b/i,
	/\bhave we (?:seen|done|tried|hit|fixed)\b/i,
	/\bdid we (?:ever|already)\b/i,
	/\blast (?:time|session)\b/i,
	/\bwe(?:'ve| have) (?:seen|done|tried|hit|fixed)\b/i,
	/\bremember (?:when|that|the)\b/i,
	/\bwhat happened with\b/i,
	/\bin (?:the|a) past session\b/i,
	/\bpreviously (?:we|I|you)\b/i,
	/\bearlier (?:session|we)\b/i,
];

interface Hit {
	when?: string;
	source?: string;
	session?: string;
	text?: string;
	score?: number;
}

function gated(text: string): boolean {
	const prompt = text.trim();
	if (prompt.length < 12 || prompt.startsWith("/")) return false;
	return GATE.some((pattern) => pattern.test(prompt));
}

function format(query: string, hits: Hit[]): string | undefined {
	const useful = hits.filter((hit) => typeof hit.text === "string" && hit.text.length > 0);
	if (useful.length === 0) return undefined;
	const lines = [
		`Earlier sessions may already answer this ("${query.slice(0, 120)}").`,
		"Quoted from the memory archive — verify before trusting it:",
	];
	useful.slice(0, MAX_HITS).forEach((hit, index) => {
		// A docs hit names a file, so the model can `read` the rest of it; an
		// archive hit names a session, which is all a transcript has.
		const where = hit.source?.startsWith("docs/")
			? `${hit.source}/${hit.session}.md`
			: [hit.when?.slice(0, 16), hit.source, hit.session].filter(Boolean).join(" · ");
		const text = (hit.text ?? "").replace(/\s+/g, " ");
		lines.push(`${index + 1}. [${where}] ${text}`);
	});
	lines.push("`recall` searches further, and `mem why <slug>` traces a learnings entry.");
	return lines.join("\n");
}

/** Race with a timeout, and clear the timer so a print run can exit. */
async function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T | undefined> {
	let timer: ReturnType<typeof setTimeout> | undefined;
	try {
		return await Promise.race([
			promise,
			new Promise<undefined>((resolve) => {
				timer = setTimeout(() => resolve(undefined), ms);
			}),
		]);
	} finally {
		if (timer) clearTimeout(timer);
	}
}

export default function (pi: ExtensionAPI) {
	let pending: Promise<Hit[] | undefined> | undefined;
	let pendingFor: string | undefined;
	const cache = new Map<string, Hit[] | undefined>();

	const start = (prompt: string, ctx: ExtensionContext) => {
		const key = prompt.trim();
		if (cache.has(key)) {
			pending = Promise.resolve(cache.get(key));
			pendingFor = key;
			return;
		}
		pendingFor = key;
		pending = (async () => {
			try {
				const result = await pi.exec(
					MEM_BIN,
					["recall", key, "--days", String(DAYS), "--mode", "semantic",
					 "--snippet", String(SNIPPET), "--json"],
					{ timeout: RECALL_TIMEOUT_MS, signal: ctx.signal },
				);
				if (result.code !== 0) return undefined;
				const parsed = JSON.parse(result.stdout) as unknown;
				return Array.isArray(parsed) ? (parsed as Hit[]) : undefined;
			} catch {
				return undefined;
			}
		})().then((hits) => {
			cache.set(key, hits);
			return hits;
		});
	};

	pi.on("session_start", async () => {
		cache.clear();
		pending = undefined;
		pendingFor = undefined;
	});

	pi.on("input", async (event, ctx) => {
		if (event.source === "extension") return { action: "continue" as const };
		if (!gated(event.text)) return { action: "continue" as const };
		start(event.text, ctx);
		return { action: "continue" as const };
	});

	pi.on("before_agent_start", async (event, ctx) => {
		if (event.messageType !== "user" || !event.prompt) return;
		const key = event.prompt.trim();
		// The prompt that started this run may differ from the one `input` saw
		// (a template expanded, a skill command ran), so only use a recall that
		// was started for this exact text.
		if (pendingFor !== key || !pending) return;
		const hits = await withTimeout(pending, WAIT_MS);
		if (!hits || hits.length === 0) return;
		const content = format(key, hits);
		if (!content) return;
		if (ctx.hasUI) ctx.ui.setStatus(STATUS_KEY, `recall ${Math.min(hits.length, MAX_HITS)}`);
		return { message: { customType: "memory-recall", content, display: false } };
	});

	pi.on("agent_settled", async (_event, ctx) => {
		if (ctx.hasUI) ctx.ui.setStatus(STATUS_KEY, undefined);
	});
}
