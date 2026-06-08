#!/usr/bin/env bash
set -euo pipefail

PROFILE="/nix/var/nix/profiles/system"

case "$(uname)" in
    Darwin) D=darwin ;;
    *) D=linux ;;
esac

p_epoch() {
    case $D in
        darwin) date -j -f "%Y-%m-%d %H:%M:%S" "$1" +%s ;;
        *) date -d "$1" +%s ;;
    esac
}

f_epoch() {
    case $D in
        darwin) date -r "$1" +"$2" ;;
        *) date -d "@$1" +"$2" ;;
    esac
}

off_date() {
    local fmt="$1" span="$2" unit="$3"
    case $D in
        darwin) date -v"-${span}${unit:0:1}" +"$fmt" ;;
        *) date -d "-${span} ${unit}" +"$fmt" ;;
    esac
}

gens=$(nix-env --list-generations -p "$PROFILE" 2>/dev/null || true)
[ -z "$gens" ] && exit 0

entries=()
while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*([0-9]+)[[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]+([0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
        g="${BASH_REMATCH[1]}"
        ds="${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
        ep=$(p_epoch "$ds")
        entries+=("$g|$ep|$(f_epoch "$ep" "%Y%m")|$(f_epoch "$ep" "%Y%V")|$(f_epoch "$ep" "%Y")")
    fi
done <<< "$gens"

IFS=$'\n' entries=($(sort -t'|' -k2 -rn <<<"${entries[*]}")); unset IFS

now=$(date +%s)

weekly_keys=()
for w in 0 1 2 3; do
    weekly_keys+=("$(off_date "%Y%V" "$w" "week")")
done

monthly_keys=()
for m in 0 1 2 3 4 5; do
    monthly_keys+=("$(off_date "%Y%m" "$m" "month")")
done

yearly_keys=()
for y in 0 1 2; do
    yearly_keys+=("$(off_date "%Y" "$y" "year")")
done

in_keep() { local g="$1"; for k in "${keep[@]}"; do [ "$k" = "$g" ] && return 0; done; return 1; }
in_arr() { local v="$1"; shift; for e in "$@"; do [ "$e" = "$v" ] && return 0; done; return 1; }

keep=()

for i in "${!entries[@]}"; do
    [ "$i" -ge 5 ] && break
    keep+=("${entries[$i]%%|*}")
done

added_weeks=()
for entry in "${entries[@]}"; do
    IFS='|' read -r g ep ym yw y <<< "$entry"
    in_keep "$g" && continue
    in_arr "$yw" "${weekly_keys[@]}" || continue
    in_arr "$yw" "${added_weeks[@]}" && continue
    keep+=("$g"); added_weeks+=("$yw")
done

added_months=()
for entry in "${entries[@]}"; do
    IFS='|' read -r g ep ym yw y <<< "$entry"
    in_keep "$g" && continue
    in_arr "$ym" "${monthly_keys[@]}" || continue
    in_arr "$ym" "${added_months[@]}" && continue
    keep+=("$g"); added_months+=("$ym")
done

added_years=()
for entry in "${entries[@]}"; do
    IFS='|' read -r g ep ym yw y <<< "$entry"
    in_keep "$g" && continue
    in_arr "$y" "${yearly_keys[@]}" || continue
    in_arr "$y" "${added_years[@]}" && continue
    keep+=("$g"); added_years+=("$y")
done

to_delete=()
for entry in "${entries[@]}"; do
    g="${entry%%|*}"
    in_keep "$g" && continue
    to_delete+=("$g")
done

if [ ${#to_delete[@]} -eq 0 ]; then
    echo "[prune-generations] No generations to delete from $PROFILE" >&2
    exit 0
fi

echo "[prune-generations] Deleting generations ${to_delete[*]} from $PROFILE" >&2
nix-env --delete-generations -p "$PROFILE" "${to_delete[@]}"
