from __future__ import annotations

import argparse
import asyncio
import json
import sys

from what_changed import cache, config, display, fetch, metadata, summarize, urls
from what_changed.differ import PackageChange, run_diff

cfg = config.Config()
no_cache = False


async def _fetch_for(c: PackageChange, cl_url: str | None, idx: int) -> tuple[int, list[str] | None]:
    global no_cache
    if not no_cache:
        cached = cache.get_summary(c.name, c.old_version, c.new_version, cfg)
        if cached is not None:
            return idx, cached

    bullets = None
    if cl_url:
        raw = None
        if not no_cache:
            raw = cache.get_changelog(cl_url, cfg)
        if raw is None:
            raw = await fetch.fetch_changelog(cl_url, cfg)
            if not no_cache:
                cache.set_changelog(cl_url, raw, cfg)
        if raw:
            bullets = await summarize.summarize(c.name, raw, cfg)
            if not no_cache:
                cache.set_summary(c.name, c.old_version, c.new_version, bullets, cfg)
    elif not no_cache:
        cache.set_summary(c.name, c.old_version, c.new_version, None, cfg)
    return idx, bullets


async def main():
    global cfg, no_cache
    parser = argparse.ArgumentParser(description="Show package changelogs after nix rebuilds")
    parser.add_argument("old_system", nargs="?", help="Old system closure path")
    parser.add_argument("new_system", nargs="?", help="New system closure path")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    parser.add_argument("--brief", action="store_true", help="Compact output, no bullet points")
    parser.add_argument("--no-cache", action="store_true", help="Skip cache, fetch fresh summaries")
    args = parser.parse_args()
    no_cache = args.no_cache

    if not args.old_system or not args.new_system:
        parser.print_help()
        sys.exit(1)

    old_system, new_system = args.old_system, args.new_system
    cfg = config.load()
    changes = run_diff(old_system, new_system)
    if not changes:
        return

    max_width = max(len(c.name) for c in changes) + 2
    max_width = max(max_width, 18)

    with display.progress_bar(len(changes)) as update:

        pkg_names = [c.name for c in changes]
        batch = metadata.get_metadata_batch(pkg_names)
        metas: dict[int, tuple[str | None, str | None]] = {}
        for i, c in enumerate(changes):
            info = batch.get(c.name, {})
            desc = info.get("description")
            if not desc and c.name == "darwin-system":
                desc = "nix-darwin system closure"
            if not desc and c.name == "what-changed":
                desc = "Show nix system package changelogs using LLM"
            cl_url = info.get("changelog")
            if cl_url:
                cl_url = await urls.patch_release_tag(cl_url, c.new_version, cfg)
            if not cl_url:
                cl_url = await urls.guess_url(c.name, c.new_version, cfg)
            metas[i] = (desc, cl_url)
            update(advance=1, desc=c.name)

        sem = asyncio.Semaphore(4)

        async def run(c: PackageChange, cl_url: str | None, idx: int):
            async with sem:
                return await _fetch_for(c, cl_url, idx)

        tasks = [
            asyncio.create_task(run(c, metas[i][1], i))
            for i, c in enumerate(changes)
        ]
        results: dict[int, list[str] | None] = {}
        errors: dict[int, str | None] = {}

        for coro in asyncio.as_completed(tasks):
            try:
                idx, bullets = await coro
                results[idx] = bullets
            except Exception as e:
                idx = next(i for i, t in enumerate(tasks) if t is coro)
                results[idx] = None
                errors[idx] = str(e)[:60]
            update(advance=1, desc=changes[idx].name)

    if args.json:
        data = []
        for i, c in enumerate(changes):
            desc, _ = metas[i]
            data.append({
                "name": c.name,
                "old_version": c.old_version,
                "new_version": c.new_version,
                "description": desc,
                "bullets": results.get(i),
                "error": errors.get(i),
            })
        print(json.dumps(data, indent=2))
        return

    if args.brief:
        for i, c in enumerate(changes):
            print(f"  {c.name:<{max_width}} {c.old_version} → {c.new_version}")
        return

    display.show_header(len(changes))
    for i, c in enumerate(changes):
        desc, _ = metas[i]
        bullets = results.get(i)
        err = errors.get(i)
        display.show_package(
            c.name, c.old_version, c.new_version,
            desc, bullets, max_width, error=err,
        )
    display.show_footer(len(changes))


def entry():
    asyncio.run(main())


if __name__ == "__main__":
    entry()
