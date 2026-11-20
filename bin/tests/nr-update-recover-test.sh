#!/usr/bin/env bash
# nr-update-recover tests — a re-run of `nr --update` must undo the files its
# previous, interrupted run half-wrote, and touch nothing else.
#
# Same throwaway layout as bin/tests/nr-guard-test.sh:
#
#   <root>/.local/share/dotfiles/bare        bare git dir, work tree = <root>
#   <root>/<files>                           the apply checkout
#
#   bash ~/bin/tests/nr-update-recover-test.sh
set -uo pipefail

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

RECOVER=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/nr-update-recover
T=/tmp/nr-update-recover-tests
pass=0
fail=0

ok() { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }

setup() {
	rm -rf "$T"
	mkdir -p "$T/.local/share/dotfiles" "$T/.config/nix/modules/overlays/x"
	git init -q --bare "$T/.local/share/dotfiles/bare"
	git --git-dir="$T/.local/share/dotfiles/bare" --work-tree="$T" config core.bare false
	git --git-dir="$T/.local/share/dotfiles/bare" --work-tree="$T" config user.name t
	git --git-dir="$T/.local/share/dotfiles/bare" --work-tree="$T" config user.email t@t
	printf 'lock1\n' >"$T/.config/nix/flake.lock"
	printf 'pins1\n' >"$T/.config/nix/flake-pins.json"
	printf 'pin1\n' >"$T/.config/nix/modules/overlays/x/default.nix"
	printf 'a1\n' >"$T/a.conf"
	g add .config/nix/flake.lock .config/nix/flake-pins.json \
		.config/nix/modules/overlays/x/default.nix a.conf
	g commit -q -m init
	git --git-dir="$T/.local/share/dotfiles/bare" branch -M main
}

g() { git -C "$T" --git-dir="$T/.local/share/dotfiles/bare" --work-tree="$T" "$@"; }

recover() {
	out=$(NR_RECOVER_ROOT=$T HOME=$T GIT_CONFIG_NOSYSTEM=1 bash "$RECOVER" 2>&1)
	status=$?
}

echo "nr-update-recover"

# 1. A clean tree is a first run: silent, exit 0.
setup
recover
[ "$status" -eq 0 ] && ok "clean tree exits 0" || bad "clean tree exited $status"
[ -z "$out" ] && ok "clean tree says nothing" || bad "clean tree spoke: $out"

# 2. Interrupted during `nix flake update`: flake.lock half-written.
setup
printf 'lock-halfwritten\n' >"$T/.config/nix/flake.lock"
recover
[ "$status" -eq 0 ] && ok "recovers a half-written flake.lock" || bad "exited $status: $out"
[ "$(cat "$T/.config/nix/flake.lock")" = lock1 ] && ok "restored the lock from main" \
	|| bad "kept the half-written lock: $(cat "$T/.config/nix/flake.lock")"
printf '%s' "$out" | grep -q 'recovering an interrupted update' && ok "says what it did" || bad "silent recovery"

# 3. Interrupted during the update scripts: the pin registry half-written.
setup
printf 'pins-halfwritten\n' >"$T/.config/nix/flake-pins.json"
recover
[ "$status" -eq 0 ] && ok "recovers a half-written registry" || bad "exited $status"
[ "$(cat "$T/.config/nix/flake-pins.json")" = pins1 ] && ok "restored the registry from main" \
	|| bad "kept $(cat "$T/.config/nix/flake-pins.json")"

# 4. The rendered pin block in flake.nix is regenerated too.
setup
printf 'edited\n' >"$T/.config/nix/flake.nix"
g add .config/nix/flake.nix
g commit -q -m "add flake.nix"
printf 'half-rendered\n' >"$T/.config/nix/flake.nix"
recover
[ "$(cat "$T/.config/nix/flake.nix")" = edited ] && ok "restored flake.nix from main" \
	|| bad "kept $(cat "$T/.config/nix/flake.nix")"

# 5. An overlay pin is not an update's own output: it may be a hand edit beside a
#    bump, so it must survive. nr-guard, which runs next, is what judges it.
setup
printf 'pin-handedit\n' >"$T/.config/nix/modules/overlays/x/default.nix"
recover
[ "$status" -eq 0 ] && ok "an overlay edit is not its business" || bad "exited $status"
[ "$(cat "$T/.config/nix/modules/overlays/x/default.nix")" = pin-handedit ] \
	&& ok "left the overlay edit alone" || bad "touched an overlay edit"
[ -z "$out" ] && ok "and says nothing about it" || bad "spoke: $out"

# 6. `nr-pins` is a script people edit (5824dcd), so it is never restored.
setup
printf 'nr-pins-v1\n' >"$T/.config/nix/nr-pins"
g add .config/nix/nr-pins
g commit -q -m "add nr-pins"
printf 'mid-edit\n' >"$T/.config/nix/nr-pins"
recover
[ "$(cat "$T/.config/nix/nr-pins")" = mid-edit ] && ok "left a mid-edit nr-pins alone" \
	|| bad "discarded nr-pins"

# 7. Mixed: the leftovers are restored, the hand edit is still there for the guard.
setup
printf 'lock-halfwritten\n' >"$T/.config/nix/flake.lock"
printf 'pin-handedit\n' >"$T/.config/nix/modules/overlays/x/default.nix"
recover
[ "$(cat "$T/.config/nix/flake.lock")" = lock1 ] && ok "restored the lock" || bad "kept the half-written lock"
[ "$(cat "$T/.config/nix/modules/overlays/x/default.nix")" = pin-handedit ] && ok "kept the hand edit" \
	|| bad "touched the hand edit"

printf '\n== summarized: %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
