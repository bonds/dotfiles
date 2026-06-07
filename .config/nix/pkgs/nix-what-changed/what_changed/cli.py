from __future__ import annotations

import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

from what_changed import cache, config, display, fetch, metadata, summarize, urls
from what_changed.differ import PackageChange, run_diff

cfg = config.Config()


def _meta_for(c: PackageChange) -> tuple[str | None, str | None]:
    cl_url = metadata.get_changelog_url(c.name)
    desc = metadata.get_description(c.name)
    if not desc and c.name == "darwin-system":
        desc = "nix-darwin system closure"
    if not cl_url:
        cl_url = urls.guess_url(c.name, c.new_version, cfg)
    return desc, cl_url


def _fetch_for(c: PackageChange, cl_url: str | None, idx: int) -> tuple[int, list[str] | None]:
    cached = cache.get_summary(c.name, c.old_version, c.new_version, cfg)
    if cached is not None:
        return idx, cached

    bullets = None
    if cl_url:
        raw = cache.get_changelog(cl_url, cfg)
        if raw is None:
            raw = fetch.fetch_changelog(cl_url, cfg)
            cache.set_changelog(cl_url, raw, cfg)
        if raw:
            bullets = summarize.summarize(c.name, raw, cfg)
            cache.set_summary(c.name, c.old_version, c.new_version, bullets, cfg)
    else:
        cache.set_summary(c.name, c.old_version, c.new_version, None, cfg)
    return idx, bullets


def main():
    global cfg
    args = sys.argv[1:]
    if len(args) < 2:
        print("Usage: what-changed <old-store-path> <new-store-path>", file=sys.stderr)
        print(file=sys.stderr)
        print("  Shows release notes for packages updated between two system closures.", file=sys.stderr)
        print(file=sys.stderr)
        print("  Automatically called by 'nr' when the system closure changes.", file=sys.stderr)
        sys.exit(1)

    old_system, new_system = args[0], args[1]
    cfg = config.load()
    changes = run_diff(old_system, new_system)
    if not changes:
        return

    max_width = max(len(c.name) for c in changes) + 2
    max_width = max(max_width, 18)

    spin_thread, spin_stop, spin_done = display.run_spinner(len(changes))

    metas = {}
    for i, c in enumerate(changes):
        metas[i] = _meta_for(c)
        spin_done[0] += 1

    results: dict[int, list[str] | None] = {}
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = {}
        for i, c in enumerate(changes):
            _, cl_url = metas[i]
            futures[pool.submit(_fetch_for, c, cl_url, i)] = i
        for future in as_completed(futures):
            try:
                idx, bullets = future.result()
                results[idx] = bullets
            except Exception:
                pass
            spin_done[0] += 1

    display.stop_spinner(spin_thread, spin_stop)

    display.show_header(len(changes))
    for i, c in enumerate(changes):
        desc, _ = metas[i]
        bullets = results.get(i)
        display.show_package(
            c.name, c.old_version, c.new_version,
            desc, bullets, max_width,
        )
    display.show_footer(len(changes))


if __name__ == "__main__":
    main()
