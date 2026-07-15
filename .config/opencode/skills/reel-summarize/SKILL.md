# Reel Summarizer

Summarize Instagram Reels from a URL. Use when the user shares an Instagram
Reel link and wants to know what it's about without watching it.

**Trigger patterns:**
- User provides a URL containing `instagram.com/reel/` or `instagr.am/reel/`
- User asks "summarize this reel", "what is this reel about", "what's in this Instagram"

**Procedure:**

Run in **three phases**, each a separate bash call, so the user sees progress
between each. Always use the PYTHONPATH override since the nix package is stale.

### Phase 1: Metadata (fast ~1-2s)

Tell the user "→ fetching metadata..." then run:

```
PYTHONPATH="/Users/scott/.config/nix/pkgs/reel-summarize:$PYTHONPATH" reel-summarize --stage metadata <url>
```

This returns just the author and caption within ~1-2 seconds. **STOP here.** Present the caption to the user as a clearly formatted text message (e.g. "**Posted by:** ..." / "**Caption:** ..."). Do NOT proceed to Phase 2 until the user sees the caption or acknowledges. The caption is the fast part — let them read it before the slow work starts.

On **exit 3** (no session): tell the user "Instagram session expired — log into
Instagram in Zen (Personal workspace), then I'll retry." Then retry phase 1.

### Phase 2: Download + extract

Tell the user "→ downloading and extracting..." then run:

```
PYTHONPATH="/Users/scott/.config/nix/pkgs/reel-summarize:$PYTHONPATH" reel-summarize --stage download <url>
```

On **exit 2** (missing model): run `ollama pull llava:7b && ollama pull qwen2.5:7b` then retry.

### Phase 3: Process (transcribe, vision, summarize)

Run:

```
PYTHONPATH="/Users/scott/.config/nix/pkgs/reel-summarize:$PYTHONPATH" reel-summarize --stage process <url>
```

Capture stdout as the summary and present it to the user.

### If state is stale

State is stored in `/tmp/reel-summarize-stage/state.json`. If a phase fails,
run all three phases in order. If only phase 1 succeeded, run phases 2 and 3.

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
