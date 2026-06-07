from __future__ import annotations

import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

from what_changed import display, fetch, metadata, summarize, urls
from what_changed.differ import PackageChange, run_diff


def _process(c: PackageChange, idx: int) -> tuple[int, str | None, list[str] | None]:
    changelog_url = metadata.get_changelog_url(c.name)
    description = metadata.get_description(c.name)
    if not description and c.name == "darwin-system":
        description = "nix-darwin system closure"

    if not changelog_url:
        changelog_url = urls.guess_url(c.name, c.new_version)

    bullets = None
    if changelog_url:
        raw_text = fetch.fetch_changelog(changelog_url)
        if raw_text:
            bullets = summarize.summarize(c.name, raw_text)

    return idx, description, bullets


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        print("Usage: what-changed <old-store-path> <new-store-path>", file=sys.stderr)
        print(file=sys.stderr)
        print("  Shows release notes for packages updated between two system closures.", file=sys.stderr)
        print(file=sys.stderr)
        print("  Automatically called by 'nr' when the system closure changes.", file=sys.stderr)
        sys.exit(1)

    old_system, new_system = args[0], args[1]
    changes = run_diff(old_system, new_system)
    if not changes:
        return

    max_width = max(len(c.name) for c in changes) + 2
    max_width = max(max_width, 18)

    spin_thread, spin_stop, spin_done = display.run_spinner(len(changes))

    results: dict[int, tuple[str | None, list[str] | None]] = {}
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = [pool.submit(_process, c, i) for i, c in enumerate(changes)]
        for future in as_completed(futures):
            try:
                idx, description, bullets = future.result()
                results[idx] = (description, bullets)
            except Exception:
                pass
            spin_done[0] += 1

    display.stop_spinner(spin_thread, spin_stop)

    display.show_header(len(changes))
    for i, c in enumerate(changes):
        description, bullets = results.get(i, (None, None))
        display.show_package(
            c.name, c.old_version, c.new_version,
            description, bullets, max_width,
        )

    display.show_footer(len(changes))


if __name__ == "__main__":
    main()
