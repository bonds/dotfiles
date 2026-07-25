"""Fetch MCP server — fetches URLs and returns clean text content"""

import httpx
from mcp.server import Server
from mcp.types import Tool, TextContent
from mcp.server.streamable_http_manager import StreamableHTTPSessionManager

server = Server("web-fetch")


@server.list_tools()
async def list_tools():
    return [
        Tool(
            name="fetch",
            description="Fetch a URL and return its content as clean text",
            inputSchema={
                "type": "object",
                "properties": {
                    "url": {
                        "type": "string",
                        "description": "URL to fetch",
                    },
                    "max_length": {
                        "type": "integer",
                        "description": "Maximum characters to return",
                        "default": 10000,
                        "maximum": 50000,
                    },
                },
                "required": ["url"],
            },
        ),
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list:
    if name != "fetch":
        raise ValueError(f"Unknown tool: {name}")

    url = arguments["url"]
    max_length = min(arguments.get("max_length", 10000), 50000)

    if not url.startswith(("http://", "https://")):
        url = "https://" + url

    headers = {
        "User-Agent": "Mozilla/5.0 (compatible; MCP-Fetch/1.0)",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
    }

    async with httpx.AsyncClient(follow_redirects=True, timeout=30.0) as client:
        resp = await client.get(url, headers=headers)
        resp.raise_for_status()
        content_type = resp.headers.get("content-type", "")

        if "text/html" in content_type or "application/xhtml" in content_type:
            text = html_to_text(resp.text)
        elif "application/json" in content_type:
            import json

            text = json.dumps(resp.json(), indent=2)
        else:
            text = resp.text

    text = text.strip()[:max_length]
    if not text:
        return [TextContent(type="text", text="No content returned from URL.")]

    return [
        TextContent(
            type="text",
            text=f"Content from {url}:\n\n{text}",
        )
    ]


def html_to_text(html: str) -> str:
    """Convert HTML to readable text by stripping tags."""
    import re

    text = re.sub(r"<script[^>]*>.*?</script>", "", html, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<style[^>]*>.*?</style>", "", text, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<nav[^>]*>.*?</nav>", "", text, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<footer[^>]*>.*?</footer>", "", text, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<header[^>]*>.*?</header>", "", text, flags=re.DOTALL | re.IGNORECASE)

    text = re.sub(r"<br\s*/?>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"</p>", "\n\n", text, flags=re.IGNORECASE)
    text = re.sub(r"</h[1-6]>", "\n\n", text, flags=re.IGNORECASE)
    text = re.sub(r"<li>", "  * ", text, flags=re.IGNORECASE)
    text = re.sub(r"</li>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"</tr>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"</td>", " | ", text, flags=re.IGNORECASE)
    text = re.sub(r"</th>", " | ", text, flags=re.IGNORECASE)

    text = re.sub(r"<[^>]+>", "", text)

    text = re.sub(r"\n\s*\n\s*\n+", "\n\n", text)
    text = re.sub(r"&nbsp;", " ", text)
    text = re.sub(r"&amp;", "&", text)
    text = re.sub(r"&lt;", "<", text)
    text = re.sub(r"&gt;", ">", text)
    text = re.sub(r"&quot;", '"', text)

    lines = [line.strip() for line in text.split("\n")]
    text = "\n".join(line for line in lines if line)

    return text


session_manager = StreamableHTTPSessionManager(
    server,
    json_response=True,
    stateless=True,
)


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

    if scope["type"] == "http":
        if scope["path"] == "/sse":
            if scope["method"] == "OPTIONS":
                await send({
                    "type": "http.response.start",
                    "status": 200,
                    "headers": [
                        (b"access-control-allow-origin", b"*"),
                        (b"access-control-allow-methods", b"GET, POST, OPTIONS"),
                        (b"access-control-allow-headers", b"*"),
                        (b"access-control-max-age", b"600"),
                    ],
                })
                await send({"type": "http.response.body", "body": b""})
                return

            orig_send = send

            async def cors_send(message):
                if message["type"] == "http.response.start":
                    headers = list(message.get("headers", []))
                    headers.append((b"access-control-allow-origin", b"*"))
                    headers.append((b"access-control-allow-methods", b"GET, POST, OPTIONS"))
                    headers.append((b"access-control-allow-headers", b"*"))
                    message = {**message, "headers": headers}
                await orig_send(message)

            await session_manager.handle_request(scope, receive, cors_send)
        else:
            await send({
                "type": "http.response.start",
                "status": 404,
                "headers": [(b"content-type", b"text/plain")],
            })
            await send({
                "type": "http.response.body",
                "body": b"Not Found",
            })


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8891, log_level="info")
