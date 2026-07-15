from __future__ import annotations

import base64
import json
import sys

from reel_summarize.config import Config


def _encode_image(path: str) -> str:
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


_VISION_PROMPT = (
    "Extract all visible on-screen text verbatim from this image, "
    "then describe the scene in one sentence. "
    'Output JSON with keys "text" (array of strings) and "scene" (string).'
)


def _call_ollama_vision(image_b64: str, cfg: Config) -> dict:
    import httpx

    payload = {
        "model": cfg.vision_model,
        "prompt": _VISION_PROMPT,
        "images": [image_b64],
        "stream": False,
        "options": {"num_gpu": 99},
    }
    try:
        resp = httpx.post(
            f"{cfg.host}/api/generate",
            json=payload,
            timeout=cfg.timeout,
        )
        resp.raise_for_status()
        text = resp.json().get("response", "")
        text = text.strip()
        if text.startswith("```"):
            text = text.split("\n", 1)[-1]
            text = text.rsplit("```", 1)[0]
        try:
            parsed = json.loads(text)
            if isinstance(parsed, dict):
                return parsed
            if isinstance(parsed, list):
                return {"text": parsed, "scene": ""}
            return {"text": [text], "scene": ""}
        except json.JSONDecodeError:
            return {"text": [text], "scene": ""}
    except httpx.TimeoutException as e:
        print(f"  timeout: frame took too long ({e})", file=sys.stderr)
        return {"text": [], "scene": ""}
    except httpx.RequestError as e:
        print(f"  error: cannot reach Ollama at {cfg.host}: {e}", file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f"  vision error: {e}", file=sys.stderr)
        return {"text": [], "scene": ""}


def analyze_frames(frames: list[str], cfg: Config) -> list[dict]:
    results = []
    total = len(frames)
    for i, path in enumerate(frames):
        img_b64 = _encode_image(path)
        result = _call_ollama_vision(img_b64, cfg)
        results.append({
            "frame": path,
            "text": result.get("text", []),
            "scene": result.get("scene", ""),
        })
        print(f"  scanned frame {i+1}/{total}", file=sys.stderr, flush=True)
    return results


def format_vision_timeline(frames: list[str], vision_results: list[dict], fps: int = 1) -> str:
    lines = []
    for i, vr in enumerate(vision_results):
        timestamp = i / fps
        text_lines = vr.get("text", [])
        scene = vr.get("scene", "")
        parts = []
        if text_lines:
            parts.append(f"text: {text_lines}")
        if scene:
            parts.append(f"scene: {scene}")
        if parts:
            lines.append(f"    [t={timestamp:.0f}s] {'; '.join(parts)}")
    return "\n".join(lines)
