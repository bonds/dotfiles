"""Reel Summarize MCP server — summarizes Instagram Reels via local models.

Exposes two tools:

- ``start_summarize_reel(url)`` — queues a job, returns ``{job_id, status}``
- ``get_reel_summary(job_id)`` — returns ``{status, result?}`` for polling

The pipeline (yt-dlp → ffmpeg → whisper → VL frames → summary) runs in a
background thread so the MCP call returns immediately.

Transport mirrors ``mcp-searxng-search`` (streamable HTTP at ``/sse``). Optional
bearer-token auth: if ``REEL_SUMMARIZE_MCP_TOKEN`` is set, every request must
carry ``Authorization: Bearer <token>``.
"""

from __future__ import annotations

import asyncio
import json
import os
import threading
import time
import uuid

from mcp.server import Server
from mcp.types import Tool, TextContent
from mcp.server.streamable_http_manager import StreamableHTTPSessionManager

from reel_summarize.config import load as load_config
from reel_summarize.pipeline import run_structured

server = Server("reel-summarize")

# ---------------------------------------------------------------------------
# In-memory job store
# ---------------------------------------------------------------------------
# Each job: { "status": "queued"|"running"|"done"|"error",
#             "result": <dict or None>, "error": <str or None>,
#             "created_at": <float>, "updated_at": <float> }
_jobs: dict[str, dict] = {}
_jobs_lock = threading.Lock()

# ---------------------------------------------------------------------------
# Background worker — picks queued jobs and runs them
# ---------------------------------------------------------------------------

def _worker_loop():
    """Single background thread that processes queued jobs."""
    while True:
        job_id = None
        # Find next queued job
        with _jobs_lock:
            for jid, job in _jobs.items():
                if job["status"] == "queued":
                    job_id = jid
                    job["status"] = "running"
                    job["updated_at"] = time.time()
                    break
        if job_id is None:
            time.sleep(1)
            continue
        # Run the pipeline
        try:
            cfg = load_config()
            url = _jobs[job_id]["url"]
            max_frames = _jobs[job_id].get("max_frames")
            fps = _jobs[job_id].get("frames_per_second")
            if max_frames is not None:
                cfg.max_frames = int(max_frames)
            if fps is not None:
                cfg.frames_per_second = int(fps)
            result = run_structured(url, cfg)
            with _jobs_lock:
                _jobs[job_id].update(
                    status="done",
                    result=result,
                    updated_at=time.time(),
                )
        except Exception as e:
            with _jobs_lock:
                _jobs[job_id].update(
                    status="error",
                    error=str(e),
                    updated_at=time.time(),
                )


_worker_thread = threading.Thread(target=_worker_loop, daemon=True)
_worker_thread.start()

# ---------------------------------------------------------------------------
# Token auth
# ---------------------------------------------------------------------------

def _token() -> str | None:
    token = os.environ.get("REEL_SUMMARIZE_MCP_TOKEN", "").strip()
    return token or None


def _authorized(headers: list[tuple[bytes, bytes]]) -> bool:
    token = _token()
    if token is None:
        return True  # auth disabled unless a token is configured
    expected = f"Bearer {token}".encode()
    for key, value in headers:
        if key.lower() == b"authorization" and value == expected:
            return True
    return False

# ---------------------------------------------------------------------------
# Tool definitions
# ---------------------------------------------------------------------------

@server.list_tools()
async def list_tools():
    return [
        Tool(
            name="start_summarize_reel",
            description=(
                "Queue an Instagram Reel for summarization. Returns a job_id "
                "immediately. The pipeline (download → transcribe → vision → "
                "summary) runs in the background. Poll with get_reel_summary."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "url": {
                        "type": "string",
                        "description": "Instagram Reel URL",
                    },
                    "max_frames": {
                        "type": "integer",
                        "description": "Maximum frames to analyze (default 10)",
                        "minimum": 1,
                        "maximum": 30,
                    },
                    "frames_per_second": {
                        "type": "integer",
                        "description": "Frame sampling rate (default 1)",
                        "minimum": 1,
                        "maximum": 5,
                    },
                },
                "required": ["url"],
            },
        ),
        Tool(
            name="get_reel_summary",
            description=(
                "Poll for the result of a previously queued reel summarization "
                "job. Returns status (queued|running|done|error) and the result "
                "when complete."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "job_id": {
                        "type": "string",
                        "description": "Job ID returned by start_summarize_reel",
                    },
                },
                "required": ["job_id"],
            },
        ),
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list:
    if name == "start_summarize_reel":
        url = arguments["url"]
        job_id = uuid.uuid4().hex[:12]
        with _jobs_lock:
            _jobs[job_id] = {
                "url": url,
                "status": "queued",
                "result": None,
                "error": None,
                "max_frames": arguments.get("max_frames"),
                "frames_per_second": arguments.get("frames_per_second"),
                "created_at": time.time(),
                "updated_at": time.time(),
            }
        payload = {
            "job_id": job_id,
            "status": "queued",
            "message": "Job queued. Poll get_reel_summary for results.",
        }
        return [TextContent(type="text", text=json.dumps(payload, indent=2))]

    elif name == "get_reel_summary":
        job_id = arguments["job_id"]
        with _jobs_lock:
            job = _jobs.get(job_id)
        if job is None:
            return [TextContent(
                type="text",
                text=json.dumps({"error": f"Unknown job_id: {job_id}"}),
            )]

        payload: dict = {
            "job_id": job_id,
            "status": job["status"],
        }

        if job["status"] == "done":
            r = job["result"]
            payload["result"] = {
                "url": r["url"],
                "author": r["author"],
                "caption": r["caption"],
                "transcript": r["transcript"],
                "vision_timeline": r["vision_timeline"],
                "duration": r["duration"],
                "summary": r["summary"],
                "model": r["model"],
                "vision_model": r["vision_model"],
            }
        elif job["status"] == "error":
            payload["error"] = job["error"]

        return [TextContent(type="text", text=json.dumps(payload, indent=2))]

    else:
        raise ValueError(f"Unknown tool: {name}")


# ---------------------------------------------------------------------------
# streamable HTTP transport (mirrors mcp-searxng-search)
# ---------------------------------------------------------------------------

session_manager = StreamableHTTPSessionManager(server, json_response=True, stateless=True)

_CORS_HEADERS = [
    (b"access-control-allow-origin", b"*"),
    (b"access-control-allow-methods", b"GET, POST, OPTIONS"),
    (b"access-control-allow-headers", b"*"),
    (b"access-control-max-age", b"600"),
]


async def _send_response(send, status, headers=(), body=b""):
    await send({
        "type": "http.response.start",
        "status": status,
        "headers": list(headers),
    })
    await send({"type": "http.response.body", "body": body})


async def app(scope, receive, send):
    if scope["type"] == "lifespan":
        async with session_manager.run():
            await send({"type": "lifespan.startup.complete"})
            while True:
                message = await receive()
                if message["type"] == "lifespan.shutdown":
                    break
            await send({"type": "lifespan.shutdown.complete"})
        return

    if scope["type"] != "http" or scope["path"] != "/sse":
        await _send_response(send, 404, [(b"content-type", b"text/plain")], b"Not Found")
        return

    if scope["method"] == "OPTIONS":
        await _send_response(send, 200, _CORS_HEADERS)
        return

    if not _authorized(scope.get("headers", [])):
        await _send_response(send, 401, [(b"content-type", b"text/plain")], b"Unauthorized")
        return

    if scope["method"] == "GET":
        await _send_response(send, 204, [(b"access-control-allow-origin", b"*")])
        return

    orig_send = send

    async def cors_send(message):
        if message["type"] == "http.response.start":
            headers = list(message.get("headers", []))
            for h in _CORS_HEADERS:
                headers.append(h)
            message = {**message, "headers": headers}
        await orig_send(message)

    await session_manager.handle_request(scope, receive, cors_send)


def main():
    import uvicorn

    host = os.environ.get("REEL_SUMMARIZE_MCP_HOST", "0.0.0.0")
    port = int(os.environ.get("REEL_SUMMARIZE_MCP_PORT", "8892"))
    uvicorn.run(app, host=host, port=port, log_level="info")


if __name__ == "__main__":
    main()
