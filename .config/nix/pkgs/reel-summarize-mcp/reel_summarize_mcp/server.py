"""Reel Summarize MCP server — summarizes Instagram Reels via local models.

Exposes one tool, ``summarize_reel(url)``, which runs the shared reel-summarize
pipeline (yt-dlp download → ffmpeg audio/frames → whisper transcription → VL
frame analysis → final synthesis) and returns structured JSON.

Transport mirrors ``mcp-searxng-search`` (streamable HTTP at ``/sse``). Optional
bearer-token auth: if ``REEL_SUMMARIZE_MCP_TOKEN`` is set, every request must
carry ``Authorization: Bearer <token>``.
"""

from __future__ import annotations

import asyncio
import json
import os

from mcp.server import Server
from mcp.types import Tool, TextContent
from mcp.server.streamable_http_manager import StreamableHTTPSessionManager

from reel_summarize.config import load as load_config
from reel_summarize.pipeline import run_structured

server = Server("reel-summarize")


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


@server.list_tools()
async def list_tools():
    return [
        Tool(
            name="summarize_reel",
            description=(
                "Download an Instagram Reel and summarize it: transcribes the audio "
                "with whisper, analyzes sampled frames with a vision model, and "
                "synthesizes a prose summary. Returns the summary, caption, author, "
                "transcript, vision timeline, duration, and models used."
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
        )
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list:
    if name != "summarize_reel":
        raise ValueError(f"Unknown tool: {name}")

    url = arguments["url"]
    cfg = load_config()
    if arguments.get("max_frames") is not None:
        cfg.max_frames = int(arguments["max_frames"])
    if arguments.get("frames_per_second") is not None:
        cfg.frames_per_second = int(arguments["frames_per_second"])

    result = await asyncio.to_thread(run_structured, url, cfg)

    payload = {
        "url": result["url"],
        "author": result["author"],
        "caption": result["caption"],
        "transcript": result["transcript"],
        "vision_timeline": result["vision_timeline"],
        "duration": result["duration"],
        "summary": result["summary"],
        "model": result["model"],
        "vision_model": result["vision_model"],
    }
    text = json.dumps(payload, ensure_ascii=False, indent=2)
    return [TextContent(type="text", text=text)]


# --- streamable HTTP transport (mirrors mcp-searxng-search) ---

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
