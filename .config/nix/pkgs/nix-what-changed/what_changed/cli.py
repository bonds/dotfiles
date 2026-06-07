from __future__ import annotations

import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

from what_changed import cache, config, display, fetch, metadata, summarize, urls
from what_changed.differ import PackageChange, run_diff

cfg = config.Config()


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

    with display.progress_bar(len(changes)) as update:

        pkg_names = [c.name for c in changes]
        batch = metadata.get_metadata_batch(pkg_names)
        metas: dict[int, tuple[str | None, str | None]] = {}
        for i, c in enumerate(changes):
            info = batch.get(c.name, {})
            desc = info.get("description")
            if not desc and c.name == "darwin-system":
                desc = "nix-darwin system closure"
            cl_url = info.get("changelog")
            if cl_url:
                cl_url = urls.patch_release_tag(cl_url, c.new_version, cfg)
            if not cl_url:
                cl_url = urls.guess_url(c.name, c.new_version, cfg)
            metas[i] = (desc, cl_url)
            update(advance=1, desc=c.name)

        results: dict[int, list[str] | None] = {}
        errors: dict[int, str | None] = {}

        with ThreadPoolExecutor(max_workers=4) as pool:
            futures = {}
            for i, c in enumerate(changes):
                _, cl_url = metas[i]
                futures[pool.submit(_fetch_for, c, cl_url, i)] = i
            for future in as_completed(futures):
                try:
                    idx, bullets = future.result()
                    results[idx] = bullets
                except Exception as e:
                    idx = futures[future]
                    results[idx] = None
                    errors[idx] = str(e)[:60]
                update(advance=1, desc=changes[idx].name)

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


if __name__ == "__main__":
    main()
