# Reel Summarizer

Summarize Instagram Reels from a URL. Use when the user shares an Instagram
Reel link and wants to know what it's about without watching it.

**Trigger patterns:**
- User provides a URL containing `instagram.com/reel/` or `instagr.am/reel/`
- User asks "summarize this reel", "what is this reel about", "what's in this Instagram"

**Procedure:**

Run in two phases so the user sees progress — each phase is a separate bash call:

### Phase 1: Download

Tell the user "→ starting download..." then run:

```
PYTHONPATH="/Users/scott/.config/nix/pkgs/reel-summarize:$PYTHONPATH" reel-summarize --stage download <url>
```

Wait for completion. On success (exit 0), tell the user "→ download done, now processing..."

On **exit 3** (download failure): tell the user "Instagram session expired — log into Instagram in Zen (Personal workspace), then I'll retry." Then retry phase 1.

On **exit 2** (missing model): run `ollama pull llava:7b && ollama pull qwen2.5:7b` then retry.

### Phase 2: Process (transcribe, vision, summarize)

Run:

```
PYTHONPATH="/Users/scott/.config/nix/pkgs/reel-summarize:$PYTHONPATH" reel-summarize --stage process <url>
```

Wait for completion. Capture stdout (the summary) and present it. If any stderr progress lines appear, include them for context.

### If a phase fails or the URL is the same as a previous attempt

If phase 1 already completed but you're retrying, just run phase 2. The state is
stored in `/tmp/reel-summarize-stage/state.json` — if it's stale or missing,
re-run phase 1 first.

**If the default `reel-summarize` fails with "cannot access post / empty response":**
The installed binary may be stale. Use the PYTHONPATH override (shown above).

**Known issues & workarounds:**

| Issue | Workaround |
|-------|-----------|
| `max_frames = 60` makes it too slow | Change `max_frames` in `~/.config/reel-summarize/config.toml` or rebuild nix |
| Vision model times out per-frame | Ensure `llava:7b` is pulled (not `llama3.2-vision:11b`) |
| Nix package stale (missing fixes) | Use PYTHONPATH override above, or rebuild with `nr` |
| ollama slow on M2 | Verify GPU layers via `ps aux \| grep llama-server` (should see `-ngl 99`) |

**Notes:**
- Runs entirely locally via Ollama + whisper
- Must have ollama running with `llava:7b` and `qwen2.5:7b` pulled
- Automatically detects cookies from Zen browser's Personal workspace
