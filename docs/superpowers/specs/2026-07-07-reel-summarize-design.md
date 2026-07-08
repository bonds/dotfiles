# Reel-Summarize: Local Instagram Reel Summarizer

Date: 2026-07-07
Status: Design approved

## Goal

Build a CLI tool that takes an Instagram Reel URL and returns a concise prose
summary of what the reel is about — combining spoken audio transcription,
on-screen overlay text (OCR), visual scene descriptions, and the post caption.
All processing happens locally via Ollama + mlx-whisper. Wire it so `opencode`
can invoke it as a tool on accismus.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| LLM backend | Local-only (Ollama) | Zero API keys, private, already have Ollama |
| Transcription | mlx-whisper (Apple Silicon) | Fastest on M-series Mac, laptop-only |
| OCR strategy | Per-frame vision (qwen2-vl) | Each frame individually via Ollama, best per-frame detail |
| Input scope | Instagram Reels only | Tight scope, no photo/carousel/TikTok |
| Output format | Concise prose to stdout (5-10 sentences) | Opencode skill just reads it directly |
| Packaging | Nix-managed Python package (like what-changed) | Follow existing pattern in dotfiles repo |
| Opencode wiring | Bin script + skill (SKILL.md) | Script standalone, skill tells LLM how to invoke it |
| Non-Mac fallback | None (meta.broken on non-aarch64-darwin) | mlx-whisper Apple Silicon only; defer if needed |
| Per-frame parallelism | Sequential (no async batch in v1) | Reels short (~15-90 frames), acceptable latency |
| Disk caching | None in v1 | No retry cache; re-run re-downloads |

## Architecture

### Directory layout

```
~/.config/nix/pkgs/reel-summarize/
├── pyproject.toml
├── default.nix
├── flake.nix              # standalone sub-flake, mirroring what-changed
├── flake.lock
├── module.nix             # programs.reel-summarize.enable
├── tests/
│   └── test_cli.py
└── reel_summarize/
    ├── __init__.py
    ├── __main__.py         # python -m reel_summarize
    ├── cli.py              # argparse, entry point
    ├── config.py           # frame rate, model names, ollama host
    ├── pipeline.py         # orchestrates stages
    └── stages/
        ├── download.py     # yt-dlp wrapper
        ├── audio_extract.py # ffmpeg 16kHz mono wav
        ├── frame_extract.py # ffmpeg 1fps frame sampling
        ├── transcribe.py   # mlx-whisper
        ├── vision.py       # per-frame qwen2-vl via ollama HTTP API
        ├── caption.py      # yt-dlp --dump-json metadata
        └── summarize.py    # qwen2.5 final summary
```

### Wiring in the dotfiles flake

- `pkgs/reel-summarize/default.nix` — nix derivation, aarch64-darwin only
- `modules/home/reel-summarize.nix` — home-manager module (programs.reel-summarize.enable)
- `flake.nix` — add to overlays or packages output
- `hosts/accismus/configuration.nix` — enable `programs.reel-summarize.enable = true`

### Opencode wiring

- `~/.config/opencode/skills/reel-summarize/SKILL.md` — markdown LLM instructions

### Repo integration

- `~/AGENTS.md` — add reel-summarize section alongside what-changed docs

## CLI surface

```
reel-summarize <url>
reel-summarize <url> --keep-artifacts
reel-summarize <url> --frames-per-second 2
reel-summarize --help
reel-summarize --preflight          # check prereqs: yt-dlp, ffmpeg, ollama, models
```

Exit codes: 0 success, 1 generic error, 2 missing prerequisite, 3 download error.

### Config file (~/.config/reel-summarize/config.toml)

```toml
host = "http://localhost:11434"
vision_model = "qwen2-vl:7b"
summarize_model = "qwen2.5:7b"
whisper_model = "small"
frames_per_second = 1
max_frames = 60
```

ENV overrides: `REEL_SUMMARIZE_OLLAMA_HOST`, `REEL_SUMMARIZE_VISION_MODEL`,
`REEL_SUMMARIZE_MODEL`, `REEL_SUMMARIZE_WHISPER_MODEL`.

## Pipeline

```
1. yt-dlp <url>           → video.mp4 + metadata.json (caption, author, duration)
2. ffmpeg video.mp4       → audio.wav (16kHz mono)
3. ffmpeg video.mp4       → frames/*.jpg (1fps, capped at max_frames)
4. mlx-whisper audio.wav  → transcript segments [{start, end, text}]
5. per frame: qwen2-vl    → per-frame {text: [lines], scene: "..."} JSON
6. qwen2.5(transcript + per-frame OCR + scene + caption)
                           → concise prose summary → stdout
7. cleanup /tmp/reel-<id>/ (unless --keep-artifacts)
```

### Prompt design

**Vision prompt** (per frame, sent to qwen2-vl as the `prompt` field):

```
Extract all visible on-screen text verbatim from this image,
then describe the scene in one sentence.
Output JSON with keys "text" (array of strings) and "scene" (string).
```

**Final summary prompt** (sent to qwen2.5):

```
You are summarizing an Instagram Reel. Inputs below:
- Author: {author}
- Original caption: {caption}
- Spoken audio transcript: {transcript}
- Per-frame on-screen text + scene descriptions:
    [t=0s] text: {lines}; scene: {description}
    [t=2s] text: {lines}; scene: {description}
    ...

Write a concise prose summary (5–10 sentences) of what the reel is about.
Include both what's said and what's shown on screen.
Do not use headers or bullet points — just prose.
```

### Progress output (to stderr)

```
→ downloading video...
→ extracting audio...
→ extracting frames...
→ transcribing audio (mlx-whisper)...
→ scanning 45 frames (qwen2-vl)...   # updated as each frame completes
→ summarizing (qwen2.5)...
```

## Testing

- **Unit tests**: CLI arg parsing, URL validation, prompt template generation
- **Pipeline tests**: mocked ollama, mocked yt-dlp, mocked ffmpeg — verify
  correct data flows between stages
- No network/ollama/whisper/ffmpeg required in test suite
- `nix flake check` runs format-check + pytest (mirrors what-changed)
- Full end-to-end: manual only (needs real reel URL, ollama running)

## Error handling

- yt-dlp error → exit 3, print URL diagnostics
- ollama not running → exit 2, suggest `ollama serve`
- model missing → exit 2, suggest `ollama pull <model>`
- 0 frames extracted → log warning, produce audio-only summary
- Network / filesystem errors → exit 1, print stderr detail

## Out of scope (v1)

- Photo/carousel post support
- TikTok / YouTube Shorts
- `--save` markdown note to disk
- Disk caching across runs
- Async batched vision inference
- Non-Mac fallback (faster-whisper)
