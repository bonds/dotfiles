#!/usr/bin/env bash
# MCP server test — the interface Osaurus launches as a stdio provider.
#
# Everything here goes through the real shim (`~/bin/mem-mcp`) over a real
# subprocess, because the failures that matter are protocol-shaped: a server that
# answers `tools/list` but hangs on `tools/call` looks fine until a model calls
# it. Osaurus also called the probe tool twice in one session, so idempotence is
# asserted rather than assumed.
#
#   bash ~/bin/tests/mcp-test.sh
set -uo pipefail

python3 - <<'MCPEOF'
import json
import os
import pathlib
import subprocess
import sys

MCP = os.path.expanduser("~/bin/mem-mcp")
RAW = pathlib.Path(os.path.expanduser("~/.local/share/agents/raw"))

passed = 0
failed = 0


def check(label: str, condition: bool, detail: str = "") -> None:
    global passed, failed
    if condition:
        passed += 1
        print(f"  PASS  {label}")
    else:
        failed += 1
        print(f"  FAIL  {label}{(' — ' + detail) if detail else ''}")


server = subprocess.Popen([MCP], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL)


def call(payload: dict) -> dict:
    server.stdin.write((json.dumps(payload) + "\n").encode())
    server.stdin.flush()
    line = server.stdout.readline()
    if not line:
        raise SystemExit("server closed the connection")
    return json.loads(line)


print("== mcp: handshake, tools, calls, errors ==")

init = call({"jsonrpc": "2.0", "id": 1, "method": "initialize",
             "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                        "clientInfo": {"name": "test", "version": "0"}}})
check("initialize names the server", init["result"]["serverInfo"]["name"] == "mem",
      str(init["result"].get("serverInfo")))

server.stdin.write(b'{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
server.stdin.flush()

tools = call({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
names = sorted(t["name"] for t in tools["result"]["tools"])
check("exposes recall, show and learnings", names == ["learnings", "recall", "show"], str(names))
check("every tool has a schema",
      all(t.get("inputSchema", {}).get("type") == "object" for t in tools["result"]["tools"]))

recall_payload = {"query": "pipe masks exit code", "limit": 3}
first = call({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
              "params": {"name": "recall", "arguments": recall_payload}})
text = first["result"]["content"][0]["text"]
check("recall finds a known-item", "pipe-masks" in text, text[:80])
check("recall is not marked as an error", not first["result"].get("isError"))

again = call({"jsonrpc": "2.0", "id": 4, "method": "tools/call",
              "params": {"name": "recall", "arguments": recall_payload}})
check("recall is idempotent (the client retries)",
      again["result"]["content"][0]["text"] == text)

manifest = next(iter(sorted(RAW.glob("sessions/*/*/*/*/session.json"))), None)
if manifest:
    harness = manifest.parts[-5]
    session = manifest.parent.name
    shown = call({"jsonrpc": "2.0", "id": 5, "method": "tools/call",
                  "params": {"name": "show",
                             "arguments": {"anchor": f"session://{harness}/{session}#turn-0"}}})
    body = shown["result"]["content"][0]["text"]
    check("show resolves a real anchor", session in body and not shown["result"].get("isError"),
          body[:80])

missing = call({"jsonrpc": "2.0", "id": 6, "method": "tools/call",
                "params": {"name": "show", "arguments": {"anchor": "session://nope/none"}}})
check("a bad anchor is an error result, not a crash",
      missing["result"].get("isError") is True, missing["result"]["content"][0]["text"])

unknown_tool = call({"jsonrpc": "2.0", "id": 7, "method": "tools/call",
                     "params": {"name": "nope", "arguments": {}}})
check("an unknown tool is an error result", unknown_tool["result"].get("isError") is True)

unknown_method = call({"jsonrpc": "2.0", "id": 8, "method": "nope/method"})
check("an unknown method returns -32601",
      unknown_method.get("error", {}).get("code") == -32601, str(unknown_method))

ping = call({"jsonrpc": "2.0", "id": 9, "method": "ping"})
check("ping answers", ping.get("result") == {})

server.terminate()
print(f"\nsummarized: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
MCPEOF
