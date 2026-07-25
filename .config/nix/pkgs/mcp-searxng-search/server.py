"""SearXNG MCP server — provides web_search tool for llama.cpp web UI"""

import contextlib

import httpx
from mcp.server import Server
from mcp.types import Tool, TextContent
from mcp.server.streamable_http_manager import StreamableHTTPSessionManager
from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.middleware.cors import CORSMiddleware
from starlette.routing import Route

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


@contextlib.asynccontextmanager
async def lifespan(app):
    async with session_manager.run():
        yield


async def handle_mcp(request):
    await session_manager.handle_request(
        request.scope, request.receive, request._send
    )


app = Starlette(
    routes=[
        Route("/sse", endpoint=handle_mcp, methods=["GET", "POST"]),
    ],
    lifespan=lifespan,
    middleware=[
        Middleware(
            CORSMiddleware,
            allow_origins=["*"],
            allow_methods=["*"],
            allow_headers=["*"],
        ),
    ],
)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8890, log_level="info")
