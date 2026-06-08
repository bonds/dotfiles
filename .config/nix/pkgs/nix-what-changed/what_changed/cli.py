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
verbose = False


Profile = "/nix/var/nix/profiles/system"
_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def _usage_gen():
    print("Usage: what-changed -N        (diff current vs N gens ago)", file=__import__("sys").stderr)
    print("       what-changed -N -M     (diff N gens ago vs M gens ago)", file=__import__("sys").stderr)


def _usage_date():
    print("Usage: what-changed YYYY-MM-DD              (current vs gen after date)", file=__import__("sys").stderr)
    print("       what-changed YYYY-MM-DD YYYY-MM-DD   (gen after first vs second)", file=__import__("sys").stderr)


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


def _gen_for_date(date_str: str) -> tuple[str, int, float]:
    """Return (store_path, gen_number, timestamp) for nearest generation on or after *date_str*."""
    import datetime
    target_ts = datetime.datetime.strptime(date_str, "%Y-%m-%d").timestamp()
    best_gen = best_ts = best_path = None
    for entry in os.scandir("/nix/var/nix/profiles"):
        m = re.fullmatch(r"system-(\d+)-link", entry.name)
        if not m:
            continue
        st = entry.stat(follow_symlinks=False)
        if st.st_mtime >= target_ts:
            if best_gen is None or st.st_mtime < best_ts:
                best_gen = int(m.group(1))
                best_ts = st.st_mtime
                best_path = os.readlink(entry.path)
    if best_gen is None:
        # fall back to oldest available
        for entry in os.scandir("/nix/var/nix/profiles"):
            m = re.fullmatch(r"system-(\d+)-link", entry.name)
            if not m:
                continue
            n = int(m.group(1))
            if best_gen is None or n < best_gen:
                best_gen = n
                best_ts = os.lstat(entry.path).st_mtime
                best_path = os.readlink(entry.path)
    return best_path, best_gen, best_ts


async def _fetch_for(c: PackageChange, cl_url: str | None, idx: int) -> tuple[int, list[str] | None]:
    global no_cache
    if not no_cache:
        cached = cache.get_summary(c.name, c.old_version, c.new_version, cfg)
        if cached is not None:
            _v(f"{c.name}: cache hit")
            return idx, cached

    _v(f"{c.name}: cl_url={cl_url}")
    bullets = None
    if cl_url:
        raw = None
        if not no_cache:
            raw = cache.get_changelog(cl_url, cfg)
        if raw is None:
            raw = await fetch.fetch_changelog(cl_url, cfg)
            _v(f"{c.name}: raw={'none' if raw is None else str(len(raw))+'b'}")
            if not no_cache:
                cache.set_changelog(cl_url, raw, cfg)
        if raw:
            raw = _prettify_gh_commits(raw)
            bullets = await summarize.summarize(c.name, raw, cfg)
            _v(f"{c.name}: bullets={'none' if bullets is None else str(len(bullets))}")
            if not no_cache:
                cache.set_summary(c.name, c.old_version, c.new_version, bullets, cfg)
    elif not no_cache:
        cache.set_summary(c.name, c.old_version, c.new_version, None, cfg)
    return idx, bullets


def _v(msg: str):
    if verbose:
        print(f"  [verbose] {msg}", file=__import__("sys").stderr)


def _prettify_gh_commits(text: str) -> str | None:
    """If *text* is a GitHub commits API response, extract readable commit messages."""
    if not text or not text.startswith("["):
        return text
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return text
    if not isinstance(data, list):
        return text
    lines = []
    for c in data:
        msg = c.get("commit", {}).get("message", "").split("\n")[0] if isinstance(c, dict) else ""
        sha = c.get("sha", "")[:7] if isinstance(c, dict) else ""
        if msg:
            lines.append(f"{sha} {msg}")
    return "\n".join(lines) if lines else text


async def main():
    global cfg, no_cache, verbose
    raw_args = sys.argv[1:]

    gen_args = [a for a in raw_args if not a.startswith("--")]
    gen_newer_num = gen_older_num = None
    gen_newer_ts = gen_older_ts = 0.0

    # Benchmark mode: --benchmark [--models ...] — handle before argparse
    if "--benchmark" in raw_args:
        from what_changed.benchmark import main as bench
        import sys as _sys
        _sys.argv[1:] = [a for a in raw_args if a != "--benchmark"]
        await bench()
        return

    # Generation offset mode: -N or -N -M
    gen_match = gen_args and re.match(r"^-(\d+)$", gen_args[0])
    # Date mode: YYYY-MM-DD or YYYY-MM-DD YYYY-MM-DD
    date_match = gen_args and _DATE_RE.match(gen_args[0])

    if gen_match:
        no_cache = "--no-cache" in raw_args
        if len(gen_args) == 1:
            newer_path, gen_newer_num, gen_newer_ts = _gen_info(0)
            older_path, gen_older_num, gen_older_ts = _gen_info(int(gen_match.group(1)))
        elif len(gen_args) == 2 and re.match(r"^-(\d+)$", gen_args[1]):
            n = int(gen_match.group(1))
            m = int(re.match(r"^-(\d+)$", gen_args[1]).group(1))
            newer_path, gen_newer_num, gen_newer_ts = _gen_info(n)
            older_path, gen_older_num, gen_older_ts = _gen_info(m)
        else:
            _usage_gen()
            sys.exit(1)
        old_system, new_system = older_path, newer_path
    elif date_match:
        no_cache = "--no-cache" in raw_args
        if len(gen_args) == 1:
            newer_path, gen_newer_num, gen_newer_ts = _gen_info(0)
            older_path, gen_older_num, gen_older_ts = _gen_for_date(gen_args[0])
        elif len(gen_args) == 2 and _DATE_RE.match(gen_args[1]):
            newer_path, gen_newer_num, gen_newer_ts = _gen_for_date(gen_args[0])
            older_path, gen_older_num, gen_older_ts = _gen_for_date(gen_args[1])
        else:
            _usage_date()
            sys.exit(1)
        old_system, new_system = older_path, newer_path
        output_json = "--json" in raw_args
        output_brief = "--brief" in raw_args
        verbose = "--verbose" in raw_args
        output_verbose = verbose
    else:
        parser = argparse.ArgumentParser(
            description="Show package changelogs after nix rebuilds",
            epilog="Date shorthand:    what-changed YYYY-MM-DD            (current vs gen after date)\n"
                   "                    what-changed YYYY-MM-DD YYYY-MM-DD (gen after first vs second)\n"
                   "Generation:         what-changed -N                    (current vs N gens ago)\n"
                   "                    what-changed -N -M                 (N gens ago vs M gens ago)\n"
                   "Benchmark:          what-changed --benchmark           (test default model)\n"
                   "                    what-changed --benchmark --models m1,m2 --samples s1,s2",
            formatter_class=argparse.RawDescriptionHelpFormatter,
        )
        parser.add_argument("old_system", nargs="?", help="Old system closure path")
        parser.add_argument("new_system", nargs="?", help="New system closure path")
        parser.add_argument("--json", action="store_true", help="Output as JSON")
        parser.add_argument("--brief", action="store_true", help="Compact output, no bullet points")
        parser.add_argument("--no-cache", action="store_true", help="Skip cache, fetch fresh summaries")
        parser.add_argument("--verbose", action="store_true", help="Show per-package debug info")
        args = parser.parse_args()
        no_cache = args.no_cache
        output_json = args.json
        output_brief = args.brief
        output_verbose = args.verbose

        if not args.old_system or not args.new_system:
            parser.print_help()
            sys.exit(1)

        old_system, new_system = args.old_system, args.new_system
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

        needs_model = cfg.backend == "ollama" and (
            no_cache or any(
                cache.get_summary(c.name, c.old_version, c.new_version, cfg) is None
                for c in changes
            )
        )
        if needs_model:
            ok = await summarize.preflight(cfg, status=lambda desc: update(advance=0, desc=desc))
            if not ok:
                update(desc="LLM unavailable — changelogs disabled")
                display._dim("  LLM unavailable — changelogs disabled")

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
