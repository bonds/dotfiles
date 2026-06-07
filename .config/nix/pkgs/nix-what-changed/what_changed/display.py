from __future__ import annotations

import shutil
import textwrap

def _dim(text: str, **kwargs):
    print(f"\033[90m{text}\033[m", **kwargs)


def _green(text: str, **kwargs):
    print(f"\033[32m{text}\033[m", **kwargs)


def _bold(text: str, **kwargs):
    print(f"\033[1m{text}\033[m", **kwargs)


def _bold_cyan(text: str, **kwargs):
    print(f"\033[36;1m{text}\033[m", **kwargs)


def _wrap(text: str, indent: str = "  ", subsequent: str = "    ") -> str:
    w = shutil.get_terminal_size().columns
    return textwrap.fill(text, w, initial_indent=indent, subsequent_indent=subsequent)


def show_header(count: int):
    print()
    _bold_cyan(f"━━━ Package Changes ({count}) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print()


def show_package(pkg: str, old_ver: str, new_ver: str,
                 description: str | None,
                 bullets: list[str] | None,
                 max_width: int):
    bold_part = f"\033[1m  {pkg:<{max_width}}\033[m"
    dim_part = f"\033[90m{old_ver}\033[m"
    green_part = f"\033[32m → {new_ver}\033[m"
    print(f"{bold_part}{dim_part}{green_part}")

    if description:
        print(_wrap(description, indent="  ↳ ", subsequent="    "))

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
