from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import sys

from what_changed import cache, config, display, fetch, metadata, summarize, urls
from what_changed.differ import PackageChange, run_diff

cfg = config.Config()
no_cache = False


Profile = "/nix/var/nix/profiles/system"


def _current_gen() -> int:
    m = re.search(r"system-(\d+)-link", os.readlink(Profile))
    if not m:
        raise ValueError("Could not find current generation")
    return int(m.group(1))


def _gen_info(offset: int) -> tuple[str, int, float]:
    """Return (store_path, generation_number, creation_timestamp)."""
    target = _current_gen() - offset
    link = f"{Profile}-{target}-link"
    st = os.lstat(link)
    return os.readlink(link), target, st.st_mtime


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
    raw_args = sys.argv[1:]

    # Check for generation-based invocation: -N or -N -M
    gen_args = [a for a in raw_args if not a.startswith("--")]
    gen_match = gen_args and re.match(r"^-(\d+)$", gen_args[0])
    gen_newer_num = gen_older_num = None
    gen_newer_ts = gen_older_ts = 0.0
    if gen_match:
        no_cache = "--no-cache" in raw_args
        if len(gen_args) == 1:
            n = int(gen_match.group(1))
            newer_path, gen_newer_num, gen_newer_ts = _gen_info(0)
            older_path, gen_older_num, gen_older_ts = _gen_info(n)
        elif len(gen_args) == 2 and re.match(r"^-(\d+)$", gen_args[1]):
            n = int(gen_match.group(1))
            m = int(re.match(r"^-(\d+)$", gen_args[1]).group(1))
            newer_path, gen_newer_num, gen_newer_ts = _gen_info(n)
            older_path, gen_older_num, gen_older_ts = _gen_info(m)
        else:
            print("Usage: what-changed -N        (diff current vs N gens ago)", file=sys.stderr)
            print("       what-changed -N -M     (diff N gens ago vs M gens ago)", file=sys.stderr)
            sys.exit(1)
        old_system, new_system = older_path, newer_path
        output_json = "--json" in raw_args
        output_brief = "--brief" in raw_args
    else:
        parser = argparse.ArgumentParser(
            description="Show package changelogs after nix rebuilds",
            epilog="Generation shorthand: what-changed -N          (current vs N gens ago)\n"
                   "                      what-changed -N -M       (N gens ago vs M gens ago)",
            formatter_class=argparse.RawDescriptionHelpFormatter,
        )
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
        output_json = args.json
        output_brief = args.brief
    cfg = config.load()
    changes = run_diff(old_system, new_system)

    if not changes:
        if gen_newer_num is not None:
            import datetime
            def fmt(ts):
                return datetime.datetime.fromtimestamp(ts).strftime("%b %d %H:%M")
            n = gen_newer_num
            o = gen_older_num
            print(f"\n  Generation {n} ({fmt(gen_newer_ts)}) → Generation {o} ({fmt(gen_older_ts)})")
            print("  ✓ No package changes between these generations.\n")
        return

    max_width = max(len(c.name) for c in changes) + 2
    max_width = max(max_width, 18)

    with display.progress_bar(len(changes)) as update:

        needs_model = cfg.backend == "ollama" and any(
            cache.get_summary(c.name, c.old_version, c.new_version, cfg) is None
            for c in changes
        )
        if needs_model:
            ok = await summarize.preflight(cfg, status=lambda desc: update(advance=0, desc=desc))
            if not ok:
                update(desc="LLM unavailable, changelogs disabled")

        pkg_names = [c.name for c in changes]
        batch = metadata.get_metadata_batch(pkg_names)
        metas: dict[int, tuple[str | None, str | None]] = {}
        for i, c in enumerate(changes):
            info = batch.get(c.name, {})
            desc = info.get("description")
            if not desc and c.name == "darwin-system":
                desc = "nix-darwin system closure"
            if not desc and c.name.startswith("nixos-system-"):
                desc = "NixOS system closure"
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

    if output_json:
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

    if output_brief:
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
