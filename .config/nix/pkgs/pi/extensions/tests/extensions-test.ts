/**
 * Logic tests for the memory extensions — the parts that can be wrong without
 * anything visibly breaking.
 *
 * `nr` never typechecks an extension and pi never unit-tests one, so these two
 * were verified by driving a model and reading what it said, which is slow,
 * costs money, and hides a false positive behind the model's goodwill (a nudge
 * claiming "then succeeded" over a retry that also failed was noticed by the
 * model, not by any check).
 *
 * The extension only needs an object with `on`, so the whole test is a fake
 * `pi` that records handlers. Run it with:
 *
 *   bun ~/.config/nix/pkgs/pi/extensions/tests/extensions-test.ts
 *
 * `import type` is erased, so bun needs none of pi's types to run this.
 */

import brief from "../memory-brief.ts";
import compact from "../auto-compact.ts";
import recall from "../memory-recall.ts";
import nudge from "../learning-nudge.ts";

type Handler = (event: any, ctx: any) => Promise<any> | any;
const REPO = "/Users/scott/.local/share/dotfiles/worktree";

let pass = 0;
let fail = 0;
function ok(label: string, condition: boolean, detail = "") {
	if (condition) {
		pass += 1;
		console.log(`  PASS  ${label}`);
	} else {
		fail += 1;
		console.log(`  FAIL  ${label}${detail ? ` — ${detail}` : ""}`);
	}
}

/** A fake pi: collects handlers, and records (or stubs) exec calls. */
function harness(extension: (pi: any) => void, exec?: (cmd: string, args: string[]) => any) {
	const handlers: Record<string, Handler[]> = {};
	const calls: string[][] = [];
	const statuses: Array<[string, string | undefined]> = [];
	const pi = {
		on: (name: string, fn: Handler) => {
			(handlers[name] ??= []).push(fn);
		},
		exec: async (cmd: string, args: string[]) => {
			calls.push([cmd, ...args]);
			if (exec) return exec(cmd, args);
			return { code: 1, stdout: "", stderr: "" };
		},
	};
	extension(pi);
	const fire = async (name: string, event: any, ctx: any = {}) => {
		const context = {
			cwd: REPO,
			hasUI: true,
			signal: undefined,
			ui: { setStatus: (key: string, value: string | undefined) => statuses.push([key, value]) },
			...ctx,
		};
		for (const fn of handlers[name] ?? []) {
			const result = await fn(event, context);
			if (result !== undefined) return result;
		}
		return undefined;
	};
	return { fire, calls, statuses };
}

const text = (body: string) => [{ type: "text", text: body }];
const failure = (command: string, message: string) => ({
	toolName: "bash",
	isError: true,
	input: { command },
	content: text(message),
});
const success = (command: string, output: string) => ({
	toolName: "bash",
	isError: false,
	input: { command },
	content: text(output),
});

console.log("\n== learning-nudge: one line when a retry fixes a failure ==");

{
	const h = harness(nudge);
	await h.fire("session_start", { reason: "startup" });
	await h.fire("tool_result", failure("cat /etc/hostname", "cat: /etc/hostname: No such file or directory"));
	await h.fire("tool_result", success("cat /etc/hosts", "127.0.0.1 localhost"));
	const out = await h.fire("turn_end", { entries: [] });
	const content = out?.entries?.at(-1)?.content ?? "";
	ok("fires on a failure then a changed retry", content.includes("succeeded with different arguments"), content);
	ok("quotes the failure", content.includes("/etc/hostname"), content);
	ok("quotes what the retry printed", content.includes("127.0.0.1 localhost"), content);
	ok("points at `learning`, not the inbox alone", content.includes("`learning`"), content);
	ok("does not display in the transcript", out?.entries?.at(-1)?.display === false);

	const again = await h.fire("turn_end", { entries: [] });
	ok("never nudges twice in a session", again === undefined);
}

{
	// The false positive that a model caught and no check did: a retry that
	// failed too must not be reported as a fix.
	const h = harness(nudge);
	await h.fire("session_start", { reason: "startup" });
	await h.fire("tool_result", failure("cat /etc/hostname", "cat: /etc/hostname: No such file or directory"));
	await h.fire("tool_result", {
		toolName: "bash",
		isError: true,
		input: { command: "cat /etc/hostname2" },
		content: text("cat: /etc/hostname2: No such file or directory"),
	});
	ok("a failure that failed again is not a fix", (await h.fire("turn_end", { entries: [] })) === undefined);
}

{
	const h = harness(nudge);
	await h.fire("session_start", { reason: "startup" });
	await h.fire("tool_result", failure("rg nope", "exit code 1"));
	await h.fire("tool_result", success("rg yep", "found"));
	ok("a search that found nothing is a result", (await h.fire("turn_end", { entries: [] })) === undefined);
}

{
	const h = harness(nudge);
	await h.fire("session_start", { reason: "startup" });
	await h.fire("tool_result", failure("cat /nope", "cat: /nope: No such file or directory"));
	await h.fire("tool_result", success("cat /nope", "same command"));
	ok("the same command twice is not a retry", (await h.fire("turn_end", { entries: [] })) === undefined);
}

{
	const h = harness(nudge);
	await h.fire("session_start", { reason: "startup" });
	await h.fire("tool_result", failure("cat /nope", "cat: /nope: No such file or directory"));
	await h.fire("tool_result", { toolName: "learning", isError: false, input: {}, content: text("wrote it") });
	await h.fire("tool_result", success("cat /nope2", "ok"));
	ok("an entry already written this session silences it", (await h.fire("turn_end", { entries: [] })) === undefined);
}

{
	const h = harness(nudge);
	await h.fire("session_start", { reason: "startup" });
	await h.fire("tool_result", failure("cat /nope", "cat: /nope: No such file or directory"));
	await h.fire("tool_result", success("cat /tmp", "files"));
	const out = await h.fire("turn_end", { entries: [] }, { cwd: "/tmp" });
	ok("no nudge outside a git repository", out === undefined);
}

console.log("\n== memory-recall: gated per-prompt recall ==");

const hits = JSON.stringify([
	{ when: "2026-11-11T21:13", source: "docs/learnings", session: "photo-backup", text: "the wrapper reported success while the SFTP login never happened", score: 0.65 },
]);

{
	const h = harness(recall, () => ({ code: 0, stdout: hits, stderr: "" }));
	await h.fire("session_start", { reason: "startup" });
	await h.fire("input", { text: "How did we fix the photo backup that did nothing?", source: "interactive" });
	await new Promise((resolve) => setTimeout(resolve, 20));
	const out = await h.fire("before_agent_start", {
		messageType: "user",
		prompt: "How did we fix the photo backup that did nothing?",
		systemPromptOptions: { sections: {} },
	});
	ok("a question about the past triggers a recall", h.calls.length === 1, JSON.stringify(h.calls));
	ok("the call asks for semantic mode", (h.calls[0] ?? []).includes("semantic"), JSON.stringify(h.calls[0]));
	const content = out?.message?.content ?? "";
	ok("injects the hit", content.includes("SFTP login never happened"), content);
	ok("injects it invisibly", out?.message?.display === false);
	ok("names the source so it can be checked", content.includes("docs/learnings"), content);
	ok("shows the footer badge", h.statuses.some(([key, value]) => key === "recall" && !!value));
}

{
	const h = harness(recall, () => ({ code: 0, stdout: hits, stderr: "" }));
	await h.fire("session_start", { reason: "startup" });
	await h.fire("input", { text: "Fix the failing test in mem-test.sh", source: "interactive" });
	await new Promise((resolve) => setTimeout(resolve, 20));
	const out = await h.fire("before_agent_start", {
		messageType: "user",
		prompt: "Fix the failing test in mem-test.sh",
		systemPromptOptions: { sections: {} },
	});
	ok("an ordinary prompt never queries", h.calls.length === 0, JSON.stringify(h.calls));
	ok("and injects nothing", out === undefined);
}

{
	const h = harness(recall, () => ({ code: 1, stdout: "", stderr: "no index" }));
	await h.fire("session_start", { reason: "startup" });
	await h.fire("input", { text: "last time we hit this error, what did we do?", source: "interactive" });
	await new Promise((resolve) => setTimeout(resolve, 20));
	const out = await h.fire("before_agent_start", {
		messageType: "user",
		prompt: "last time we hit this error, what did we do?",
		systemPromptOptions: { sections: {} },
	});
	ok("a failing recall injects nothing", out === undefined);
}

console.log("\n== memory-brief: the badge says what is broken, and nothing else ==");

/** One `mem brief --json` payload, shaped like the real one. */
function briefPayload(options: { inbox?: number; contradicting?: number; alarm?: string | null }) {
	return {
		code: 0,
		stdout: JSON.stringify({
			cwd: REPO,
			repo: "dotfiles",
			text: "memory brief",
			inbox: { count: options.inbox ?? 0, oldest_days: null },
			distill: { contradicting: options.contradicting ?? 0 },
			nightly: { alarm: options.alarm ?? null },
		}),
		stderr: "",
	};
}

async function badge(options: { inbox?: number; contradicting?: number; alarm?: string | null }) {
	const h = harness(brief, () => briefPayload(options));
	await h.fire("session_start", { reason: "startup" });
	const last = h.statuses.at(-1);
	return last?.[1];
}

ok("a healthy night with an empty inbox shows nothing", (await badge({})) === undefined);
ok(
	"a failing night job shows first",
	(await badge({ inbox: 3, alarm: "fail" })) === "nightly fail · inbox 3",
);
ok("a stale night job says how stale", (await badge({ alarm: "5d" })) === "nightly 5d");
ok(
	"the clash count still rides along",
	(await badge({ inbox: 28, contradicting: 5 })) === "inbox 28 · 5 clash",
);
ok(
	"alarm and backlog share one line",
	(await badge({ inbox: 2, contradicting: 1, alarm: "3d" })) === "nightly 3d · inbox 2 · 1 clash",
);

console.log("\n== auto-compact: 100k, and never mid-task ==");

/** Drive one `agent_settled` with a chosen context size and mode. */
async function settled(options: {
	tokens: number;
	window?: number;
	mode?: string;
	aborted?: boolean;
	idle?: boolean;
}) {
	let compacted = 0;
	const h = harness(compact);
	await h.fire("agent_settled", { aborted: options.aborted ?? false }, {
		mode: options.mode ?? "tui",
		isIdle: () => options.idle ?? true,
		getContextUsage: () => ({ tokens: options.tokens, contextWindow: options.window ?? 1_000_000 }),
		compact: () => {
			compacted += 1;
		},
	});
	return compacted;
}

ok("a small context is left alone", (await settled({ tokens: 60_000 })) === 0);
ok("99k is still under the floor", (await settled({ tokens: 99_000 })) === 0);
ok("100k compacts", (await settled({ tokens: 100_000 })) === 1);
ok("the 1M window keeps the floor, not 10% of it", (await settled({ tokens: 120_000 })) === 1);
ok("a 128k window still uses 100k", (await settled({ tokens: 100_000, window: 128_000 })) === 1);
ok("a tiny window caps at 80% of itself", (await settled({ tokens: 63_000, window: 80_000 })) === 0);
ok("...and fires just above the cap", (await settled({ tokens: 65_000, window: 80_000 })) === 1);
ok("an aborted run is not compacted", (await settled({ tokens: 400_000, aborted: true })) === 0);
ok("a print run is not compacted", (await settled({ tokens: 400_000, mode: "print" })) === 0);
ok("a busy session is not compacted", (await settled({ tokens: 400_000, idle: false })) === 0);

console.log(`\n== summarized: ${pass} passed, ${fail} failed ==\n`);
process.exit(fail === 0 ? 0 : 1);
