from __future__ import annotations

import itertools
import shutil
import sys
import textwrap
import threading
import time

def _dim(text: str, **kwargs):
    print(f"\033[90m{text}\033[m", **kwargs)


def _green(text: str, **kwargs):
    print(f"\033[32m{text}\033[m", **kwargs)


def _yellow(text: str, **kwargs):
    print(f"\033[33m{text}\033[m", **kwargs)


def _bold_cyan(text: str, **kwargs):
    print(f"\033[36;1m{text}\033[m", **kwargs)


def _wrap(text: str, indent: str = "  ", subsequent: str = "    ") -> str:
    w = shutil.get_terminal_size().columns
    return textwrap.fill(text, w, initial_indent=indent, subsequent_indent=subsequent)


def _spinner_thread(stop: threading.Event, total: int, done_ref: list[int]):
    for frame in itertools.cycle(["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]):
        if stop.is_set():
            break
        d = done_ref[0]
        if d <= total:
            sys.stdout.write(f"\r  {frame} Checking {d}/{total} packages... ")
        else:
            sys.stdout.write(f"\r  {frame} Summarizing {d - total}/{total}...   ")
        sys.stdout.flush()
        time.sleep(0.4)


def run_spinner(total: int) -> tuple[threading.Thread, threading.Event, list[int]]:
    stop = threading.Event()
    done_ref = [0]
    t = threading.Thread(target=_spinner_thread, args=(stop, total, done_ref), daemon=True)
    t.start()
    return t, stop, done_ref


def stop_spinner(t: threading.Thread, stop: threading.Event):
    stop.set()
    t.join()
    sys.stdout.write("\r" + " " * shutil.get_terminal_size().columns + "\r")
    sys.stdout.flush()


def show_header(count: int):
    print()
    _bold_cyan(f"━━━ Package Changes ({count}) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print()


def show_package(pkg: str, old_ver: str, new_ver: str,
                 description: str | None,
                 bullets: list[str] | None,
                 max_width: int):
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
    print()


def show_footer(count: int):
    _dim(f"  {count} packages updated")
    print()
