from __future__ import annotations

import base64
import json
import sys

from reel_summarize.config import Config


def _encode_image(path: str) -> str:
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


_VISION_PROMPT = (
    'Analyze this image and output JSON with keys "text", "scene", and "objects". '
    '"text" (array of strings): extract all visible on-screen text/overlays/labels verbatim; '
    "empty array if none. "
    '"scene" (string): a one-sentence description of the scene. '
    '"objects" (array): the recognizable objects, people, animals, products, logos, or text props '
    "visible in the frame; each item is an object with a \"name\" (string) and optional "
    "\"detail\" (string), e.g. {\"name\":\"microphone\",\"detail\":\"on a stand\"}. "
    'Provide all three keys; use empty values where nothing applies.'
)


def _normalize_vision(result) -> dict:
    """Ensure a vision result always has text/scene/objects keys with sane types."""
    if not isinstance(result, dict):
        if isinstance(result, list):
            result = {"text": result}
        else:
            result = {"text": [str(result)]}
    out = {
        "text": result.get("text") or [],
        "scene": result.get("scene") or "",
        "objects": result.get("objects") or [],
    }
    # Allow objects as a flat list of strings OR a list of {"name", "detail"} dicts.
    objs = []
    for o in out["objects"]:
        if isinstance(o, str):
            objs.append({"name": o, "detail": ""})
        elif isinstance(o, dict) and o.get("name"):
            objs.append({"name": str(o["name"]), "detail": str(o.get("detail") or "")})
    out["objects"] = objs
    return out


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
        print(f"  error: cannot reach LLM at {cfg.host}: {e}", file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f"  vision error: {e}", file=sys.stderr)
        return {"text": [], "scene": ""}


def _call_openai_vision(image_b64: str, cfg: Config) -> dict:
    import httpx

    host = cfg.vision_host.rstrip("/")
    payload = {
        "model": cfg.vision_model,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": _VISION_PROMPT},
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/jpeg;base64,{image_b64}"
                        },
                    },
                ],
            }
        ],
        "max_tokens": 512,
        "stream": False,
    }
    try:
        resp = httpx.post(
            f"{host}/v1/chat/completions",
            json=payload,
            timeout=cfg.timeout,
        )
        resp.raise_for_status()
        text = resp.json()["choices"][0]["message"]["content"]
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
        print(f"  error: cannot reach LLM at {cfg.host}: {e}", file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f"  vision error: {e}", file=sys.stderr)
        return {"text": [], "scene": ""}


def _call_osaurus_vision(image_b64: str, cfg: Config) -> dict:
    import httpx

    host = cfg.host.rstrip("/")
    headers = {}
    if cfg.osaurus_api_key:
        headers["Authorization"] = f"Bearer {cfg.osaurus_api_key}"

    # Use the configured vision model explicitly
    model = cfg.vision_model

    payload = {
        "model": model,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": _VISION_PROMPT},
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/jpeg;base64,{image_b64}"
                        },
                    },
                ],
            }
        ],
        "max_tokens": 512,
        "stream": False,
    }
    try:
        resp = httpx.post(
            f"{host}/v1/chat/completions",
            json=payload,
            headers=headers,
            timeout=cfg.timeout,
        )
        resp.raise_for_status()
        text = resp.json()["choices"][0]["message"]["content"]
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
        print(f"  error: cannot reach Osaurus at {cfg.host}: {e}", file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f"  vision error: {e}", file=sys.stderr)
        return {"text": [], "scene": ""}


def analyze_frames(frames: list[str], cfg: Config) -> list[dict]:
    results = []
    total = len(frames)
    if cfg.backend == "openai":
        caller = _call_openai_vision
    elif cfg.backend == "osaurus":
        caller = _call_osaurus_vision
    else:
        caller = _call_ollama_vision
    for i, path in enumerate(frames):
        img_b64 = _encode_image(path)
        result = _normalize_vision(caller(img_b64, cfg))
        results.append({
            "frame": path,
            "text": result.get("text", []),
            "scene": result.get("scene", ""),
            "objects": result.get("objects", []),
        })
        print(f"  scanned frame {i+1}/{total}", file=sys.stderr, flush=True)
    return results


def format_vision_timeline(frames: list[str], vision_results: list[dict], fps: int = 1) -> str:
    lines = []
    for i, vr in enumerate(vision_results):
        timestamp = i / fps
        text_lines = vr.get("text", [])
        scene = vr.get("scene", "")
        objects = vr.get("objects", [])
        parts = []
        if text_lines:
            parts.append(f"text: {text_lines}")
        if scene:
            parts.append(f"scene: {scene}")
        if objects:
            objs_desc = ", ".join(
                (f"{o.get('name')}{': ' + o['detail'] if o.get('detail') else ''}" for o in objects)
            )
            parts.append(f"objects: {objs_desc}")
        if parts:
            lines.append(f"    [t={timestamp:.0f}s] {'; '.join(parts)}")
    return "\n".join(lines)
