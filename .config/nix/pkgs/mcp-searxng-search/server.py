"""SearXNG MCP server — provides web_search tool for llama.cpp web UI"""

import httpx
from mcp.server import Server
from mcp.types import Tool, TextContent
from mcp.server.streamable_http_manager import StreamableHTTPSessionManager

server = Server("searxng-search")


@server.list_tools()
async def list_tools():
    return [
        Tool(
            name="web_search",
            description="Search the web using SearXNG meta search engine",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Search query",
                    },
                    "language": {
                        "type": "string",
                        "description": "Language code (e.g., en, fr, de)",
                        "default": "en",
                    },
                    "max_results": {
                        "type": "integer",
                        "description": "Maximum number of results to return",
                        "default": 5,
                        "maximum": 20,
                    },
                },
                "required": ["query"],
            },
        ),
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list:
    if name != "web_search":
        raise ValueError(f"Unknown tool: {name}")

    query = arguments["query"]
    language = arguments.get("language", "en")
    max_results = min(arguments.get("max_results", 5), 20)

    async with httpx.AsyncClient() as client:
        resp = await client.get(
            "http://localhost:8888/search",
            params={
                "q": query,
                "format": "json",
                "language": language,
                "categories": "general",
            },
            timeout=30.0,
        )
        resp.raise_for_status()
        data = resp.json()

    results = data.get("results", [])[:max_results]
    if not results:
        return [TextContent(type="text", text="No search results found.")]

    formatted = []
    for r in results:
        title = r.get("title", "No title")
        url = r.get("url", "")
        content = r.get("content", "")[:500]
        formatted.append(f"## {title}\nURL: {url}\n{content}")

    return [
        TextContent(
            type="text",
            text=(
                f'Search results for "{query}":\n\n'
                + "\n\n---\n\n".join(formatted)
            ),
        )
    ]


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
                        (b"access-control-allow-methods", b"POST, OPTIONS"),
                        (b"access-control-allow-headers", b"*"),
                        (b"access-control-max-age", b"600"),
                    ],
                })
                await send({"type": "http.response.body", "body": b""})
                return

            if scope["method"] == "GET":
                await send({
                    "type": "http.response.start",
                    "status": 204,
                    "headers": [
                        (b"access-control-allow-origin", b"*"),
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

    uvicorn.run(app, host="0.0.0.0", port=8890, log_level="info")
