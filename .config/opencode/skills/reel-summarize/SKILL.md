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

Run:

```
PYTHONPATH="/Users/scott/.config/nix/pkgs/reel-summarize:$PYTHONPATH" reel-summarize --stage metadata <url>
```

This returns the author and caption within ~1-2 seconds. Present them to the user
inline ("**Posted by:** ... / **Caption:** ...") and **immediately proceed to Phase 2**
without waiting. Do not ask for confirmation — the user wants to see the caption
early and wants the pipeline to keep going.

On **exit 3** (no session): tell the user "Instagram session expired — log into
Instagram in Zen (Personal workspace), then I'll retry." Then retry phase 1.

### Phase 2: Download + extract

Run:

```
PYTHONPATH="/Users/scott/.config/nix/pkgs/reel-summarize:$PYTHONPATH" reel-summarize --stage download <url>
```

On **exit 2** (missing model): run `bash ~/.config/nix/scripts/download-llamacpp-models.sh` or ensure the GGUF files are in `~/.cache/llama.cpp/models/`.
On **exit 3**: retry phase 1 with fresh cookies.

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
| Vision model times out per-frame | Ensure `qwen2.5-vl:7b` GGUF is in `~/.cache/llama.cpp/models/` |
| Nix package stale (missing fixes) | Use PYTHONPATH override above, or rebuild with `nr` |
| Slow on M2 | Verify GPU layers via `ps aux \| grep llama-server` (should see `-ngl 99`) |

**Notes:**
- Runs entirely locally via llama.cpp + transcribe.cpp
- Must have llama.cpp server running on `localhost:8080` and/or `localhost:8081` with GGUF models in `~/.cache/llama.cpp/models/`
- Automatically detects cookies from Zen browser's Personal workspace
