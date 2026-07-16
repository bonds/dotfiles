import re
import subprocess
import sys
from datetime import datetime

NIX_ENV = "@nix_env@"
PROFILE = "/nix/var/nix/profiles/system"


def list_generations():
    result = subprocess.run(
        [NIX_ENV, "--list-generations", "-p", PROFILE],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return []

    gens = []
    for line in result.stdout.splitlines():
        m = re.match(r"\s*(\d+)\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})", line)
        if m:
            num = int(m.group(1))
            dt = datetime.strptime(f"{m.group(2)} {m.group(3)}", "%Y-%m-%d %H:%M:%S")
            gens.append((num, dt))

    gens.sort(key=lambda x: x[1], reverse=True)
    return gens


def keep_set(gens):
    keep = set()

    for g, _ in gens[:5]:
        keep.add(g)

    now = datetime.now()
    seen_weeks = set()
    seen_months = set()
    seen_years = set()

    for g, dt in gens:
        if g in keep:
            continue

        week_key = dt.strftime("%Y-%V")
        weeks_ago = (now - dt).days // 7
        if weeks_ago < 4 and week_key not in seen_weeks:
            keep.add(g)
            seen_weeks.add(week_key)
            continue

        month_key = dt.strftime("%Y-%m")
        months_ago = (now - dt).days // 30
        if months_ago < 6 and month_key not in seen_months:
            keep.add(g)
            seen_months.add(month_key)
            continue

        year_key = dt.strftime("%Y")
        years_ago = (now - dt).days // 365
        if years_ago < 3 and year_key not in seen_years:
            keep.add(g)
            seen_years.add(year_key)
            continue

    return keep


def main():
    gens = list_generations()
    if not gens:
        return

    keep = keep_set(gens)
    to_delete = [str(g) for g, _ in gens if g not in keep]

    if not to_delete:
        print(f"[prune-generations] No generations to delete from {PROFILE}", file=sys.stderr)
        return

    print(
        f"[prune-generations] Deleting generations {' '.join(to_delete)} from {PROFILE}",
        file=sys.stderr,
    )
    subprocess.run(
        [NIX_ENV, "--delete-generations", "-p", PROFILE] + to_delete,
        timeout=60,
    )


if __name__ == "__main__":
    main()
