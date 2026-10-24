#!/usr/bin/env bun
// capture test suite — the failure-signature pickers behind the shared inbox.
//
// Three writers decide what a captured line *says*: pi's learnings-capture
// (tool failures), the opencode plugin (same, different event stream) and pi's
// corrections-capture (what the user said). Each has a heuristic that decides
// whether a failure is worth recording and which line names it. Those
// heuristics are the difference between an inbox of lessons and an inbox of
// noise, so they get regression coverage.
//
// Every case runs against a throwaway MEMORY_DIR, so the real inbox,
// ~/.agents/memory and the real `mem` store are never touched:
//
//   bash ~/bin/tests/capture-test.sh
//
// The cases encode the rules, not the wording: an error-shaped line is
// recorded (`fatal: …`, `tool: …`, a canonical phrase), prose from a file or a
// log is not, exit 1 (search found nothing) and 141 (`| head` SIGPIPE) are
// results rather than lessons, and a question is not a correction.

import { mkdtempSync, existsSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const HOME = process.env.HOME ?? "";
const LEARN = `${HOME}/.config/nix/pkgs/pi/extensions/learnings-capture.ts`;
const CORRECT = `${HOME}/.config/nix/pkgs/pi/extensions/corrections-capture.ts`;
const PLUGIN = `${HOME}/.config/opencode/plugins/memory-capture.js`;

// Fail loudly when the harness moves: a silently skipped suite is worse than
// no suite.
for (const path of [LEARN, CORRECT, PLUGIN]) {
	if (!existsSync(path)) {
		console.error(`capture-test: missing ${path}`);
		process.exit(1);
	}
}

let pass = 0;
let fail = 0;
const ok = (label) => {
	console.log(`  PASS  ${label}`);
	pass++;
};
const bad = (label, detail) => {
	console.log(`  FAIL  ${label}`);
	if (detail) console.log(`        ${detail}`);
	fail++;
};

const scratch = (prefix) => mkdtempSync(join(tmpdir(), prefix));
const candidates = (inbox) =>
	existsSync(inbox)
		? readFileSync(inbox, "utf8")
				.split("\n")
				.filter((line) => line.startsWith("- ["))
		: [];

/** One line per distinct signature means the second identical failure adds none. */
const waitFor = async (predicate, ms = 2000) => {
	const until = Date.now() + ms;
	while (Date.now() < until) {
		if (predicate()) return true;
		await new Promise((r) => setTimeout(r, 50));
	}
	return predicate();
};

// --------------------------------------------------------------- opencode --
/**
 * Drive the plugin's real event subscription. `mem` runs as a child process
 * and inherits MEMORY_DIR, so the capture lands in the scratch dir.
 */
async function opencode(c, id) {
	const dir = scratch("capture-oc-");
	process.env.MEMORY_DIR = join(dir, "memory");
	const mod = await import(`${PLUGIN}?v=${Date.now()}-${id}`);
	const events = [
		{ type: "session.tool.input.started", location: { directory: "/tmp/x" }, data: { id: "call1", name: "shell" } },
		{
			type: "session.tool.success",
			location: { directory: "/tmp/x" },
			data: {
				id: "call1",
				sessionID: "ses_regression0",
				metadata: { exit: c.exit },
				content: [{ type: "text", text: c.text }],
			},
		},
	];
	const ctx = {
		location: { directory: "/tmp/x" },
		event: {
			subscribe: async function* () {
				for (const event of events) yield event;
			},
		},
	};
	const dispose = mod.default.setup(ctx);
	const inbox = join(dir, "memory", "inbox.md");
	// A real capture is a detached `mem inbox add`; give it long enough to land
	// before deciding that nothing was written.
	if (c.want) await waitFor(() => candidates(inbox).length > 0);
	else await new Promise((r) => setTimeout(r, 600));
	dispose?.();
	return candidates(inbox).pop() ?? null;
}

// --------------------------------------------------------------------- pi --
/** Drive pi's tool_result handler with a synthetic failure. */
async function pi(c, id) {
	const dir = scratch("capture-pi-");
	process.env.MEMORY_DIR = join(dir, "memory");
	const mod = await import(`${LEARN}?v=${Date.now()}-${id}`);
	const handlers = {};
	mod.default({ on: (name, fn) => (handlers[name] = fn) });
	const ctx = { cwd: "/tmp/x", hasUI: false, sessionManager: { getSessionId: () => "regression-session" } };
	const event = {
		isError: true,
		toolName: "shell",
		content: [{ type: "text", text: `${c.text}\nExited with code ${c.exit}` }],
	};
	// The two-strike rule: the first sighting only counts, the second records.
	const times = c.twice === false ? 1 : 2;
	for (let i = 0; i < times; i++) await handlers.tool_result(event, ctx);
	const inbox = join(dir, "memory", "inbox.md");
	const lines = candidates(inbox);
	return lines.pop() ?? null;
}

/** Drive pi's input hook; true when the message was captured as a lesson. */
async function correction(text, id) {
	const dir = scratch("capture-co-");
	process.env.MEMORY_DIR = join(dir, "memory");
	const mod = await import(`${CORRECT}?v=${Date.now()}-${id}`);
	const handlers = {};
	mod.default({ on: (name, fn) => (handlers[name] = fn) });
	const ctx = {
		cwd: "/tmp/x",
		hasUI: false,
		sessionManager: { getSessionId: () => "regression-session", getBranch: () => [] },
	};
	await handlers.input({ source: "user", text }, ctx);
	return candidates(join(dir, "memory", "inbox.md")).length > 0;
}

// ---------------------------------------------------------------- fixtures --
// The two signatures that started this: the picker matched a bare keyword, so
// a file dump and a log dump supplied "fail"/"error" from prose.
const SIGNATURES = [
	{
		name: "prose from a skill dump, exit 1",
		exit: 1,
		text: "10: * This skill appends one line per failure.\n11: * tool call fails. `/distill` clusters these",
		want: null,
	},
	{
		name: "log lines, exit 1",
		exit: 1,
		text: '167828:timestamp=2026-10-24T20:06:26Z level=INFO msg="loading plugin" id=/x',
		want: null,
	},
	{
		name: "| head SIGPIPE, exit 141",
		exit: 141,
		text: "a log line that mentions error handling",
		want: null,
	},
	{
		name: "silent exit 1",
		exit: 1,
		text: "",
		want: null,
	},
	{
		name: "tool-prefixed error, exit 2",
		exit: 2,
		text: "rg: unrecognized flag --definitely-not-a-flag",
		want: /unrecognized flag/,
	},
	{
		name: "git fatal, exit 128",
		exit: 128,
		text: "usage: git rev-parse [<options>] <args>...\nfatal: Needed a single revision",
		want: /Needed a single revision/,
	},
	{
		name: "unknown option, exit 1",
		exit: 1,
		text: "unknown option -ext\nusage: x509 [-C] [-addreject arg]",
		want: /unknown option -ext/,
	},
	{
		name: "missing path, exit 1",
		exit: 1,
		text: "ls: /no-such-path-xyz: No such file or directory",
		want: /No such file/,
	},
	{
		name: "usage banner alone, exit 2",
		exit: 2,
		text: "usage: x509 [-C] [-addreject arg]",
		want: /usage: x509/,
	},
];

const CORRECTIONS = [
	{ text: "What if I don't do anything further for now?", want: false },
	{ text: "Should we always pin the version?", want: false },
	{ text: "Don't force-push, ever.", want: true },
	{ text: "no, that's wrong", want: true },
	{ text: "From now on verify with rev-parse.", want: true },
	{ text: "I think it was a touchid failure actually", want: true },
];

// ------------------------------------------------------------------- cases --
const same = (line, want) => (want === null ? line === null : line !== null && want.test(line));

console.log("\n== signatures: opencode plugin and pi record the same thing ==");
let i = 0;
for (const c of SIGNATURES) {
	for (const [name, run] of [
		["opencode", opencode],
		["pi", pi],
	]) {
		const line = await run(c, i++);
		const label = `${name}: ${c.name}`;
		if (same(line, c.want)) ok(label);
		else bad(label, line ? `captured ${JSON.stringify(line.slice(0, 90))}` : "captured nothing");
	}
}

console.log("\n== signatures: one sighting is not enough (two-strike rule) ==");
{
	const c = { exit: 2, text: "rg: unrecognized flag --one-off", want: null, twice: false };
	const line = await pi(c, "strike");
	if (line === null) ok("pi: a lone failure is not recorded");
	else bad("pi: a lone failure is not recorded", JSON.stringify(line));
}

console.log("\n== corrections: a question is not a correction ==");
for (const c of CORRECTIONS) {
	const captured = await correction(c.text, i++);
	if (captured === c.want) ok(`${c.want ? "captures" : "ignores"} ${JSON.stringify(c.text.slice(0, 46))}`);
	else bad(`${c.want ? "captures" : "ignores"} ${JSON.stringify(c.text.slice(0, 46))}`, `captured=${captured}`);
}

console.log(`\n== summarised: ${pass} passed, ${fail} failed ==\n`);
process.exit(fail === 0 ? 0 : 1);
