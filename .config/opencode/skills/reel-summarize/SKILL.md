# Reel Summarizer

Summarize Instagram Reels from a URL. Use when the user shares an Instagram
Reel link and wants to know what it's about without watching it.

**Trigger patterns:**
- User provides a URL containing `instagram.com/reel/` or `instagr.am/reel/`
- User asks "summarize this reel", "what is this reel about", "what's in this Instagram"

**Procedure:**

1. Extract the reel URL from the user's message
2. Run `reel-summarize <url>` via the bash tool
3. Capture stdout (the summary) and stderr (progress messages)
4. Present the summary to the user

**If the default `reel-summarize` fails with "cannot access post / empty response":**
The installed binary may be stale (missing cookie/gpu fixes). Use the PYTHONPATH override:
```
PYTHONPATH="/Users/scott/.config/nix/pkgs/reel-summarize:$PYTHONPATH" reel-summarize <url>
```

**Exit code handling:**
- Exit 0: success — present stdout directly
- Exit 2: missing prerequisite — tell the user to run `ollama pull llava:7b` and `ollama pull qwen2.5:7b`
- Exit 3: download failure — could be auth (cookies stale), private account, or expired URL. Regenerate cookies if needed.
- Other exit codes: print the error from stderr

**Known issues & workarounds:**

| Issue | Workaround |
|-------|-----------|
| `max_frames = 60` makes it too slow | Change `max_frames` in `~/.config/reel-summarize/config.toml` or rebuild nix |
| Vision model times out per-frame | Ensure `llava:7b` is pulled (not `llama3.2-vision:11b` — mllama arch unsupported) |
| Nix package stale (missing cookie/gpu fixes) | Use PYTHONPATH override above, or rebuild with `nr` |
| ollama slow on M2 | Check `num_gpu: 99` is in the ollama API payload (`vision.py` sets it); verify GPU layers via `ps aux \| grep llama-server` |

**Notes:**
- Runs entirely locally via Ollama + whisper (openai-whisper)
- Takes ~1-3 min to complete depending on reel length
- Must have ollama running with `llava:7b` and `qwen2.5:7b` pulled
- The `reel-summarize` binary is on PATH after `nr`
- Automatically detects cookies from Zen browser's Personal workspace (no manual login needed)
