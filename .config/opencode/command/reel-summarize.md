---
description: Summarize an Instagram Reel using local models (Ollama + whisper)
---

Run in two phases, each as a separate bash call, so the user sees progress:

1. **Download:** `PYTHONPATH="/Users/scott/.config/nix/pkgs/reel-summarize:$PYTHONPATH" reel-summarize --stage download $ARGUMENTS`
   → tell user "download done, now processing..."

2. **Process:** `PYTHONPATH="/Users/scott/.config/nix/pkgs/reel-summarize:$PYTHONPATH" reel-summarize --stage process $ARGUMENTS`
   → capture stdout as the summary and present it

If phase 1 gets exit 3 (download failure), tell the user to refresh Instagram session in Zen browser. If exit 2 (missing model), run `ollama pull llava:7b && ollama pull qwen2.5:7b` first.
