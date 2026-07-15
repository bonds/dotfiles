---
description: Summarize an Instagram Reel using local models (Ollama + whisper)
---

Run `reel-summarize $ARGUMENTS` via bash. Capture stdout (the summary) and stderr (progress). If exit code is 3 (download failure), retry with:

```
PYTHONPATH="/Users/scott/.config/nix/pkgs/reel-summarize:$PYTHONPATH" reel-summarize $ARGUMENTS
```

Present the summary to the user.
