---
description: Summarize an Instagram Reel via the sophrosyne MCP server
---

Summarize the Instagram Reel at `$ARGUMENTS` using the sophrosyne MCP server
(`sophrosyne_mcp`), NOT the local accismus pipeline.

Use the `start_summarize_reel` MCP tool with the URL. It returns the author and
caption immediately (~1-2s) and queues the heavy pipeline (download → transcribe →
vision → summary) in the background. Then poll `get_reel_summary` with the returned
job_id until status is `done`, and present the final summary to the user.

Show the caption/author as soon as you have it, and keep the user informed while
polling. Present the final summary as concise prose.

If `start_summarize_reel` returns an error mentioning download/auth failures, tell
the user they may need to refresh the Instagram session (IG cookies are sourced from
agenix on sophrosyne).
