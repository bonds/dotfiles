---
description: Summarize an Instagram Reel using local models (Ollama + whisper)
---

Run in three phases, each a separate bash call, so the user sees progress:

1. **Metadata** (~1-2s): `PYTHONPATH="/Users/scott/.config/nix/pkgs/reel-summarize:$PYTHONPATH" reel-summarize --stage metadata $ARGUMENTS`
   → show the caption/author to the user immediately

2. **Download + extract** (~20-30s): `PYTHONPATH="/Users/scott/.config/nix/pkgs/reel-summarize:$PYTHONPATH" reel-summarize --stage download $ARGUMENTS`
   → tell user "download done"

3. **Process** (~1-2min): `PYTHONPATH="/Users/scott/.config/nix/pkgs/reel-summarize:$PYTHONPATH" reel-summarize --stage process $ARGUMENTS`
   → capture stdout as the summary and present it

If phase 1 gets exit 3 (download failure), tell the user to refresh Instagram session in Zen browser. If exit 2 (missing model), run `ollama pull llava:7b && ollama pull qwen2.5:7b` first.
