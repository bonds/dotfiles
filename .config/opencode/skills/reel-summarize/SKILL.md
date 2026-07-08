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

**Exit code handling:**
- Exit 0: success — present stdout directly
- Exit 2: missing prerequisite — tell the user to run `ollama pull qwen2-vl:7b qwen2.5:7b`
- Exit 3: download failure — tell the user the URL may be private or expired
- Other exit codes: print the error from stderr

**Notes:**
- Runs entirely locally via Ollama + faster-whisper
- Takes ~30-120s to complete depending on reel length
- Must have ollama running with `qwen2-vl:7b` and `qwen2.5:7b` pulled
- The `reel-summarize` binary is on PATH after `nr`
