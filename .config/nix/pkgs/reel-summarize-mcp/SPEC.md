# reel-summarize-mcp — spec

Turn the existing `reel-summarize` pipeline into an MCP server hosted on
**sophrosyne**, exposed to the Osaurus agent on accismus. Status: implemented
per this spec.

## Current state (as found)

- `pkgs/reel-summarize` is a Python CLI. It shells out to `yt-dlp` + `ffmpeg`
  (must be on PATH), transcribes via `transcribe-cpp` (native lib via
  `TRANSCRIBE_LIBRARY`), runs per-frame vision + final synthesis against llama.cpp's
  OpenAI-compatible API. Config is env-overridable (`REEL_SUMMARIZE_*`).
- The two LLM servers live on **accismus** (Mac): text `Qwen2.5-7B` @ `127.0.0.1:8080`,
  vision `Qwen2.5-VL-7B` @ `127.0.0.1:8081`.
- sophrosyne runs a text llama.cpp **router** @ `0.0.0.0:8080` (gemma-4-31b /
  qwen3.6 models) and already hosts two MCP servers (`mcp-searxng-search` @8890,
  `mcp-fetch` @8891) as systemd services. It has **no vision model**.
- `transcribe-cpp`/`transcribe-cpp-python` are only added to `pkgs` via the
  **darwin-only** overlay, so NixOS can't resolve them from `pkgs`.

## Decisions (user-confirmed)

1. Move the **vision model to sophrosyne** so the MCP server is independent of the Mac.
   Implemented with **Qwen3-VL-2B** (Qwen2.5-VL-7B was tried, then dropped for the
   faster 2B MoE — see deployment below).
2. **IG cookies** deployed to sophrosyne via **agenix** (encrypted `.age` blob).
   Implemented — live at `/run/agenix/reel-ig-cookies`.
3. One MCP tool: `summarize_reel(url)` (sync first; async job-ID is a follow-up).
4. Toolchain deps bundled into the MCP derivation (superset) so it installs on sophrosyne.

## Design

### `run_structured()` in `reel_summarize/pipeline.py`
The pipeline printed instead of returning. Added `run_structured(url, cfg) -> dict`
reusing the same stages, returning `{url, author, caption, transcript,
vision_timeline, duration, summary, model, vision_model}`. `run()` now delegates
to it and prints — CLI and MCP share one code path.

### `pkgs/reel-summarize-mcp` (new package)
Python `buildPythonApplication` (mirrors `reel-summarize`'s style) that:
- `callPackage`s `reel-summarize` + `transcribe-cpp(-python)` **locally** so it
  builds on NixOS without the darwin overlay.
- `propagatedBuildInputs = [reel-summarize mcp httpx starlette uvicorn]`.
- Wraps with `TRANSCRIBE_LIBRARY` (`.so` on Linux, `.dylib` on macOS) and prefixes
  PATH with `yt-dlp` + `ffmpeg`.
- `server.py` mirrors `mcp-searxng-search`'s streamable-HTTP transport at `/sse`
  (port `REEL_SUMMARIZE_MCP_PORT`, default 8892), optional bearer-token auth when
  `REEL_SUMMARIZE_MCP_TOKEN` is set.

### sophrosyne deployment
- **Vision server:** `llamacpp-server.vision` (new option in
  `modules/llamacpp-server.nix`) spawns a second llama-server
  (`llamacpp-vision-server.service`, `127.0.0.1:8081`) for
  `Qwen3-VL-2B-Instruct-Q4_K_M` + mmproj, downloaded on first start under
  `/dragon/servers/llamacpp/models`. KV cache set to `q8_0` to cut memory
  (`--cache-type-k/v q8_0`).
- **Service:** `reel-summarize-mcp.service` runs as `llamacpp`, `wants`
  both llama servers, `StateDirectory=reel-summarize-mcp` + `HOME=/var/lib/...`
  for the whisper cache, env config points at `127.0.0.1:8080/8081`, backend
  `openai`. Binds **all interfaces** (`REEL_SUMMARIZE_MCP_HOST=0.0.0.0`)
  and is reachable from accismus via **Tailscale** (firewall allows port
  8892 on `tailscale0` only — not exposed on LAN or public internet).
- **IG cookies:** `age.secrets.reel-ig-cookies` + `REEL_SUMMARIZE_COOKIES` —
  implemented; a Netscape-format cookie blob is encrypted with agenix and
  mounted at `/run/agenix/reel-ig-cookies`.

### Tokens / security
- Existing sophrosyne MCP servers are unauthenticated on the LAN; first deploy
  matches that. Adding `REEL_SUMMARIZE_MCP_TOKEN` (store in Osaurus Keychain) is a
  recommended hardening follow-up once validated.

## Remaining steps
- [x] Create IG cookie blob → agenix: `age.encrypt` a Netscape `cookies.txt`,
      commit `secrets/reel-ig-cookies.age`, add `age.secrets.reel-ig-cookies`,
      uncomment `REEL_SUMMARIZE_COOKIES`.
- [x] `alejandra` + build (nixos-rebuild build on sophrosyne) + `nr --update`/switch.
- [x] Osaurus MCP provider (manual): name `sophrosyne mcp`,
      `http://sophrosyne:8892/sse` — reached directly over the **Tailscale**
      network (no SSH tunnel needed).
- [ ] Follow-ups: async job-ID + poll; point/retire the old `reel-summarizer` skill.
