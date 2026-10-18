/**
 * Learnings — record domain knowledge next to the code, in one call.
 *
 * The practice already exists (`~/AGENTS.md` -> "log surprises next to the
 * code", `/learn`, and `polyptych/docs/learnings/` with a dozen entries), but
 * it only happens in the one repo that also ships the scaffolding. The two
 * frictions that stop it everywhere else are naming the file and remembering
 * to update the index, so this tool does both deterministically: write the
 * dated entry, append the index line, create the README on first use.
 *
 * This is for *domain* knowledge — a platform quirk, an API change, an
 * undefined-behavior trap — the kind of thing a future session in this repo
 * needs. Agent-behavior lessons ("don't run the rebuild") belong in the inbox
 * that `/distill` drains, not here.
 *
 * No model calls. Refuses outside a git repository, because a learning with no
 * repo to travel with is not worth writing.
 */

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { withFileMutationQueue } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const README = `# Learnings

A running log of surprises, gotchas, and lessons learned while working in this
repository. The point is to accumulate hard-won knowledge so we do not
re-discover the same traps.

## Adding an entry

One lesson per file, named \`YYYY-MM-DD-short-slug.md\` and linked below, with:

- **Symptom** — what you observed.
- **Cause** — the underlying reason.
- **Fix / takeaway** — what to do (or avoid) next time.

Keep it short and concrete. If a lesson is superseded, update it rather than
deleting it.

## Entries

`;

/** Walk up until a `.git` exists; a learning without a repo has nowhere to live. */
function repoRoot(from: string): string | undefined {
	let dir = from;
	for (;;) {
		if (existsSync(join(dir, ".git"))) return dir;
		const parent = dirname(dir);
		if (parent === dir) return undefined;
		dir = parent;
	}
}

function today(): string {
	const now = new Date();
	const pad = (n: number) => String(n).padStart(2, "0");
	return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

function slugify(title: string): string {
	return title
		.toLowerCase()
		.replace(/[`'"“”‘’]/g, "")
		.replace(/[^a-z0-9]+/g, "-")
		.replace(/^-+|-+$/g, "")
		.slice(0, 60)
		.replace(/-+$/g, "");
}

function section(text: string): string {
	return text.trim().replace(/\n{3,}/g, "\n\n");
}

const LearningParams = Type.Object({
	title: Type.String({
		description:
			"One-line title naming the lesson, in the same voice as the index: 'macOS delivers the launch argument twice'.",
	}),
	symptom: Type.String({
		description: "What was observed, including the exact error text or the wrong behaviour.",
	}),
	cause: Type.String({
		description: "The underlying reason: platform quirk, API change, undefined behavior, wrong assumption.",
	}),
	fix: Type.String({
		description: "What to do next time, with the command or code that works.",
	}),
	slug: Type.Optional(
		Type.String({ description: "File slug (kebab-case). Derived from the title when omitted." }),
	),
});

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "learning",
		label: "Learning",
		description:
			"Record a non-obvious discovery about this codebase's platform, APIs or tools as docs/learnings/YYYY-MM-DD-slug.md and index it in docs/learnings/README.md. Use after working out something that would otherwise be re-discovered: an OS quirk, an API lifetime rule, a surprising performance cliff. Not for agent-behaviour rules.",
		promptSnippet: "Record a non-obvious platform/API discovery in docs/learnings/",
		promptGuidelines: [
			"When you work out something non-obvious about the platform, an API, or a tool — a quirk, a lifetime rule, a surprising cost — record it with `learning` before finishing. Skip it when the code already makes it obvious.",
		],
		parameters: LearningParams,
		annotations: { destructiveHint: false, idempotentHint: false, openWorldHint: false },
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const title = String(params.title ?? "").trim();
			const symptom = String(params.symptom ?? "").trim();
			const cause = String(params.cause ?? "").trim();
			const fix = String(params.fix ?? "").trim();

			if (!title || !symptom || !cause || !fix) {
				throw new Error("learning: title, symptom, cause and fix are all required");
			}

			const root = repoRoot(ctx.cwd);
			if (!root) {
				throw new Error(
					`learning: ${ctx.cwd} is not inside a git repository, so there is nowhere for this to live. Agent-behaviour lessons go to ~/.pi/agent/inbox.md; use /learn for a note without an index.`,
				);
			}

			const dir = join(root, "docs", "learnings");
			const date = today();
			const slug = slugify(String(params.slug ?? "").trim() || title);
			if (!slug) throw new Error("learning: could not derive a slug from the title; pass one explicitly");

			const filename = `${date}-${slug}.md`;
			const path = join(dir, filename);
			const readmePath = join(dir, "README.md");

			await withFileMutationQueue(path, async () => {
				await mkdir(dir, { recursive: true });

				if (existsSync(path)) {
					throw new Error(
						`learning: ${path} already exists — read it and extend that entry rather than adding a second one for the same lesson`,
					);
				}

				const body = `# ${title}\n\n**Date:** ${date}\n\n## Symptom\n\n${section(symptom)}\n\n## Cause\n\n${section(cause)}\n\n## Fix / takeaway\n\n${section(fix)}\n`;
				await writeFile(path, body, "utf8");

				let readme = "";
				try {
					readme = await readFile(readmePath, "utf8");
				} catch {
					readme = "";
				}
				if (readme.trim().length === 0) {
					readme = README;
				}
				if (!/^## Entries/m.test(readme)) {
					readme = `${readme.replace(/\n*$/, "\n")}\n## Entries\n\n`;
				}
				// Keep one blank line between the heading and the list, and one
				// entry per line.
				readme = readme.replace(/^## Entries\n(?!\n)/m, "## Entries\n\n");

				const line = `- [${date} — ${title}](${filename})\n`;
				const updated = readme.endsWith("\n") ? readme + line : `${readme}\n${line}`;
				await writeFile(readmePath, updated, "utf8");
			});

			return {
				content: [
					{
						type: "text",
						text: `Recorded ${path} and indexed it in ${readmePath}.\n\nEntry: ${date} — ${title}`,
					},
				],
				details: undefined,
			};
		},
	});
}
