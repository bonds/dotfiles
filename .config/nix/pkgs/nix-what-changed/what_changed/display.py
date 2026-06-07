from __future__ import annotations

import shutil
import textwrap
from contextlib import contextmanager

try:
    from rich.console import Console
    from rich.progress import BarColumn, Progress, SpinnerColumn, TextColumn

    _HAS_RICH = True
except ImportError:
    _HAS_RICH = False


def _dim(text: str, **kwargs):
    print(f"\033[90m{text}\033[m", **kwargs)


def _bold_cyan(text: str, **kwargs):
    print(f"\033[36;1m{text}\033[m", **kwargs)


def _wrap(text: str, indent: str = "  ", subsequent: str = "    ") -> str:
    w = shutil.get_terminal_size().columns
    return textwrap.fill(text, w, initial_indent=indent, subsequent_indent=subsequent)


@contextmanager
def progress_bar(total: int):
    """Context manager yielding an update(advance=1, desc=None) callable.

    The progress bar disappears when the context exits. Falls back to a simple
    spinner (no rich progress columns) when the ``rich`` package is unavailable.
    """
    if not _HAS_RICH:
        import itertools
        import sys
        import threading
        import time

        stop = threading.Event()
        done = [0]

        def _spin():
            for frame in itertools.cycle(["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]):
                if stop.is_set():
                    break
                d = done[0]
                if d <= total:
                    sys.stdout.write(f"\r  {frame} Checking {d}/{total}... ")
                else:
                    sys.stdout.write(f"\r  {frame} Summarizing {d - total}/{total}... ")
                sys.stdout.flush()
                time.sleep(0.4)

        t = threading.Thread(target=_spin, daemon=True)
        t.start()

        def update(advance: int = 1, desc: str | None = None):
            done[0] += advance

        try:
            yield update
        finally:
            stop.set()
            t.join()
            sys.stdout.write("\r" + " " * shutil.get_terminal_size().columns + "\r")
            sys.stdout.flush()
        return

    console = Console()
    with Progress(
        SpinnerColumn(),
        TextColumn("  {task.description}"),
        BarColumn(),
        TextColumn("{task.completed}/{task.total}"),
        console=console,
        transient=True,
    ) as progress:
        task_id = progress.add_task("Checking packages...", total=total * 2)

        def update(advance: int = 1, desc: str | None = None):
            if progress.tasks[0].completed < total:
                progress.update(task_id, advance=advance, description=desc or "Looking up...")
            else:
                progress.update(task_id, advance=advance, description=desc or "Summarizing...")

        yield update


def show_header(count: int):
    print()
    _bold_cyan(f"━━━ Package Changes ({count}) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print()


def show_package(pkg: str, old_ver: str, new_ver: str,
                 description: str | None,
                 bullets: list[str] | None,
                 max_width: int,
                 error: str | None = None):
    name_part = f"\033[1;33m  {pkg:<{max_width}}\033[m"
    dim_part = f"\033[90m{old_ver}\033[m"
    green_part = f"\033[32m → {new_ver}\033[m"
    print(f"{name_part}{dim_part}{green_part}")

    if description:
        print(f"\033[33m{_wrap(description, indent='  ↳ ', subsequent='    ')}\033[m")

    if bullets:
        max_bullets = 5
        for b in bullets[:max_bullets]:
            print(_wrap(b, indent="  • ", subsequent="    "))
        if len(bullets) > max_bullets:
            _dim(f"  … and {len(bullets) - max_bullets} more changes")
    elif error:
        _dim(f"  ⚠ {error}")
    print()


def show_footer(count: int):
    _dim(f"  {count} packages updated")
    print()
