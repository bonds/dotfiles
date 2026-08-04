class ReelError(Exception):
    """A recoverable, user-facing error in the reel-summarize pipeline.

    Raised by pipeline stages (download, transcription, etc.) instead of
    ``sys.exit(...)`` so library callers — notably the MCP server, which runs
    the pipeline in a worker thread — can surface a clean error instead of
    killing the process with a ``SystemExit``. The CLI still converts these to
    an exit code (see ``run()``/``run_stage()``).
    """


class SummaryError(ReelError):
    """The summary LLM call failed (unreachable, timeout, or bad response)."""


class DownloadError(ReelError):
    """The video could not be downloaded (network, auth/cookies, or 404)."""
