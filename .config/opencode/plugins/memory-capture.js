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
// distinct failure signature per process (a retry storm must not flood the
// inbox), and every failure is swallowed — a broken capture must never break a
// session.

import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

const MEM = join(homedir(), "bin", "mem");
const MAX_TEXT = 140;
// Per-process dedupe: the same signature is one unresolved candidate, not a log.
const seen = new Set();

function clip(text) {
  const flat = String(text ?? "").replace(/\s+/g, " ").trim();
  return flat.length > MAX_TEXT ? `${flat.slice(0, MAX_TEXT - 1)}…` : flat;
}

// A tool part carries its outcome in `state`. V1 used `state.status`; V2 also
// publishes `session.next.*` events, so accept anything that names an error.
function failureOf(part) {
  if (!part || part.type !== "tool") return null;
  const state = part.state || {};
  const status = state.status || part.status;
  if (status !== "error" && status !== "failed" && !state.error) return null;
  const detail =
    (state.error && (state.error.message || state.error)) ||
    state.output ||
    part.error ||
    "tool failed";
  return { tool: part.tool || part.name || "tool", detail: clip(detail) };
}

function capture(tool, detail, sessionID, cwd) {
  const key = `${tool}\u0000${detail}`;
  if (seen.has(key)) return;
  seen.add(key);
  if (seen.size > 200) seen.clear();
  const text = `\`${tool}\` — ${detail} — ${clip(cwd || process.cwd())}`;
  const args = [MEM, "inbox", "add", "bash", text];
  if (sessionID) args.push("--session", String(sessionID).slice(0, 8));
  try {
    execFile(MEM, args, { timeout: 5000 }, () => {});
  } catch {
    // Never let capture break the session.
  }
}

export const MemoryCapturePlugin = async () => {
  return {
    event: async ({ event }) => {
      try {
        if (!event || typeof event.type !== "string") return;
        if (event.type !== "message.part.updated" && event.type !== "session.next.tool.failed") return;
        const props = event.properties || {};
        const failure = failureOf(props.part) || failureOf(props);
        if (!failure) return;
        capture(failure.tool, failure.detail, props.sessionID, props.part?.state?.input?.cwd);
      } catch {
        // Swallowed on purpose.
      }
    },
  };
};

export default {
  id: "memory-capture",
  server: MemoryCapturePlugin,
};
