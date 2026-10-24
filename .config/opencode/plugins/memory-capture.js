// Memory capture for OpenCode — append failed tool calls to the shared inbox.
//
// The inbox at ~/.agents/memory/inbox.md is written by every harness (pi's
// extensions, this plugin, a hermes shell hook, `mem inbox add`), and drained
// by `mem distill` / `/distill`. One file, so a lesson captured in opencode is
// promotable from pi.
//
// Why a plugin and not instructions: the moment a lesson exists is the moment
// the agent is mid-debug and least likely to write it down. Capture has to be
// mechanical.
//
// Deliberately cheap and dumb: no model calls, no network, one line per
// distinct failure signature (a retry storm must not flood the inbox), and
// every failure is swallowed — a broken capture must never break a session.
//
// OpenCode 2 plugin shape: the default export needs `id` plus `setup`, and the
// event stream is consumed through `ctx.event.subscribe`. Two things changed
// from V1:
//
//   - `session.tool.failed` carries only the call id, so the tool name is
//     remembered from `session.tool.input.started`.
//   - a shell command that exits non-zero is NOT a failed tool in V2: it
//     completes, and reports the code in `metadata.exit`. Watching only
//     `session.tool.failed` would therefore miss every failing command, so a
//     completed tool with a non-zero exit is treated as a failure too.

import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

const MEM = join(homedir(), "bin", "mem");
const MAX_TEXT = 140;
// The background server is long-lived, so the name map is bounded.
const MAX_NAMES = 1000;

function clip(text) {
  const flat = String(text ?? "").replace(/\s+/g, " ").trim();
  return flat.length > MAX_TEXT ? `${flat.slice(0, MAX_TEXT - 1)}…` : flat;
}

function textOf(content) {
  if (!Array.isArray(content)) return "";
  return content
    .map((block) => (block && block.type === "text" && typeof block.text === "string" ? block.text : ""))
    .join("\n");
}

// Lines that carry no signal on their own: bash's own exit-code banner.
const NOISE = [
  /^exited with code \d+$/i,
  /^exit code \d+$/i,
  /^exit status \d+$/i,
  /^command exited with/i,
  /^\(no output\)$/i,
];
// Prefer a line that names the failure over one that echoes a path or usage.
const SIGNAL = /error|denied|not found|refus|blocked|fail|invalid|unknown|cannot|unable|no such/i;

// A shell command's failure: first line that names it, else the first real
// line, else a banner naming the exit code. Mirrors pi's learnings-capture.
function commandFailure(content, exit) {
  const lines = textOf(content)
    .replace(/\x1b\[[0-9;]*m/g, "")
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !NOISE.some((pattern) => pattern.test(line)));
  const chosen = lines.find((line) => SIGNAL.test(line)) ?? lines[0];
  // A silent exit 1 is a result, not a lesson: `rg`/`grep`/`fd`/`diff` report
  // "nothing matched" that way, and it is the biggest source of inbox noise.
  if (chosen === undefined && exit === 1) return null;
  return chosen ?? `(no output, exit ${exit})`;
}

function errorFailure(error) {
  if (!error) return "tool failed";
  if (typeof error === "string") return error;
  return error.message || error.type || "tool failed";
}

export default {
  id: "memory-capture",

  setup(ctx) {
    const controller = new AbortController();
    const names = new Map();
    // One line per distinct signature: the inbox is a set of unresolved
    // lessons, not a log. Broken capture must never break a session.
    const seen = new Set();
    const cwd = ctx?.location?.directory || process.cwd();

    const capture = (tool, detail, sessionID, directory) => {
      const signature = `${tool}\u0000${detail}`;
      if (seen.has(signature)) return;
      seen.add(signature);
      if (seen.size > 200) seen.clear();
      // argv only: the script reads its own path as argv[0], so passing MEM
      // here again makes `mem` reject its own path as the subcommand.
      const args = ["inbox", "add", `\`${tool}\``, `${detail} — ${clip(directory || cwd)}`];
      // `ses_` carries no information and would eat the whole 8-char slice.
      if (sessionID) args.push("--session", String(sessionID).replace(/^ses_/, "").slice(0, 8));
      try {
        execFile(MEM, args, { timeout: 5000 }, () => {});
      } catch {
        // Never let capture break the session.
      }
    };

    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          const data = event?.data;
          if (!data) continue;
          // One event reaches every loaded location's instance, so take the
          // path from the event itself: the line stays identical whichever
          // instance writes it (and `mem` then dedupes it).
          const directory = event.location?.directory;

          if (event.type === "session.tool.input.started") {
            if (!data.id || !data.name) continue;
            names.set(data.id, data.name);
            if (names.size > MAX_NAMES) names.delete(names.keys().next().value);
            continue;
          }

          const tool = names.get(data.id) || "tool";
          if (event.type === "session.tool.failed") {
            names.delete(data.id);
            capture(tool, clip(errorFailure(data.error)), data.sessionID, directory);
            continue;
          }

          if (event.type !== "session.tool.success") continue;
          names.delete(data.id);
          const exit = data.metadata?.exit;
          if (typeof exit !== "number" || exit === 0) continue;
          const detail = commandFailure(data.content, exit);
          if (detail) capture(tool, clip(detail), data.sessionID, directory);
        }
      } catch {
        // Subscription ends when the plugin unloads.
      }
    })();

    return () => controller.abort();
  },
};
