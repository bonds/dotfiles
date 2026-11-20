#!/usr/bin/env bash
# nr-guard tests — the checkout-state decisions `nr` makes before it builds.
#
# Every case builds a throwaway layout under /tmp and points NR_GUARD_ROOT at it,
# so the test exercises the logic rather than today's state of the real repo:
#
#   <root>/.local/share/dotfiles/bare        bare git dir, work tree = <root>
#   <root>/.local/share/dotfiles/worktree    linked worktree, branch `edit`
#   <root>/<files>                           the apply checkout
#
#   bash ~/bin/tests/nr-guard-test.sh
#
# Guard commits into the fixture's bare repo while main is also its checked-out
# branch, which git refuses unless told otherwise — the real bare repo on
# sophrosyne is configured the same way.
set -uo pipefail

# Fixture commits need an identity; set once, before any of them run.
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

GUARD=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/nr-guard
T=/tmp/nr-guard-tests
pass=0
fail=0

ok() { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }

# expect_status <label> <want-exit> -- <guard output goes to $out>
expect_exit() {
	if [ "$2" = "$status" ]; then ok "$1 (exit $2)"; else bad "$1 (exit $status, want $2)"; fi
}

expect_out() { # <label> <pattern>
	if printf '%s' "$out" | grep -qE -- "$2"; then ok "$1"; else bad "$1 — no match for /$2/ in: $out"; fi
}

expect_no_out() { # <label> <pattern>
	if printf '%s' "$out" | grep -qE -- "$2"; then bad "$1 — unexpected /$2/ in: $out"; else ok "$1"; fi
}

guard() {
	out=$(NR_GUARD_ROOT=$T GIT_CONFIG_NOSYSTEM=1 HOME=$T bash "$GUARD" 2>&1)
	status=$?
}

# A fresh repo with one commit on main holding four files, an apply checkout
# checked out at main, and an edit worktree at main.
setup() {
	rm -rf "$T"
	mkdir -p "$T/.local/share/dotfiles" "$T/sub"
	git init -q --bare "$T/.local/share/dotfiles/bare"
	git --git-dir="$T/.local/share/dotfiles/bare" --work-tree="$T" config core.bare false
	git --git-dir="$T/.local/share/dotfiles/bare" --work-tree="$T" config user.name t
	git --git-dir="$T/.local/share/dotfiles/bare" --work-tree="$T" config user.email t@t
	git --git-dir="$T/.local/share/dotfiles/bare" config receive.denyCurrentBranch ignore
	printf 'a1\n' >"$T/a.conf"
	printf 'b1\n' >"$T/sub/b.conf"
	printf 'c1\n' >"$T/sub/c.conf"
	printf 'd1\n' >"$T/d.txt"
	g add a.conf sub/b.conf sub/c.conf d.txt
	g commit -q -m init
	git --git-dir="$T/.local/share/dotfiles/bare" branch -M main
	g checkout -q main
	git --git-dir="$T/.local/share/dotfiles/bare" worktree add -q --detach "$T/.local/share/dotfiles/worktree" main
	# `edit` shares main's ref: a $HOME-side commit moves it, which is exactly the
	# "edit tree is behind main" state (and the one that reverts commits, so it
	# has to hit the stale branch, not the uncommitted-changes one).
	git -C "$T/.local/share/dotfiles/worktree" checkout -q -b edit main
}

g() { git -C "$T" --git-dir="$T/.local/share/dotfiles/bare" --work-tree="$T" "$@"; }
wt() { git -C "$T/.local/share/dotfiles/worktree" "$@"; }
WTDIR=$T/.local/share/dotfiles/worktree

# main_from <file> <content> [<file> <content>...] — commit new content for the
# given paths on top of main and move main there, leaving the apply checkout
# holding the old content: exactly "$HOME is behind main".
main_from() {
	set -e
	mkdir -p "$T/bump"
	git --git-dir="$T/.local/share/dotfiles/bare" --work-tree="$T/bump" checkout -q -f main
	while [ "$#" -gt 0 ]; do
		mkdir -p "$(dirname "$T/bump/$1")"
		printf '%s' "$2" >"$T/bump/$1"
		shift 2
	done
	git --git-dir="$T/.local/share/dotfiles/bare" --work-tree="$T/bump" add -A
	git --git-dir="$T/.local/share/dotfiles/bare" --work-tree="$T/bump" commit -q -m bump
	set +e
}

echo "nr-guard"

# 1. Nothing to do: exit 0, silent.
setup
guard
expect_exit "clean tree" 0
expect_no_out "clean tree says nothing" 'WARNING|applying'

# 2. Behind main: apply main to $HOME, leaving the rest of the checkout alone.
setup
main_from a.conf 'a2
' sub/b.conf 'b2
'
guard
expect_exit "behind main applies" 0
expect_out "behind main announces the apply" 'nr: applying [0-9a-f]+ to'
[ "$(cat "$T/a.conf")" = a2 ] && ok "behind main updated a.conf" || bad "behind main left a.conf stale"
[ "$(cat "$T/sub/b.conf")" = b2 ] && ok "behind main updated sub/b.conf" || bad "behind main left sub/b.conf stale"
[ "$(cat "$T/d.txt")" = d1 ] && ok "behind main left untouched files alone" || bad "behind main lost d.txt"

# 3. Local edits to tracked files: refuse to apply, name them, build anyway.
setup
main_from sub/b.conf 'b2
'
printf 'MINE\n' >"$T/d.txt" # content that exists nowhere in history
guard
expect_exit "local edits still build" 0
expect_out "local edits warn" 'has local edits to tracked files'
expect_out "local edits name the path" 'd\.txt'
expect_no_out "local edits do not apply" 'nr: applying'
[ "$(cat "$T/d.txt")" = MINE ] && ok "local edit survives" || bad "local edit was clobbered"
[ "$(cat "$T/sub/b.conf")" = b1 ] && ok "local edits leave the checkout alone" || bad "local edits applied main anyway"

# 4. A file main just ADDED, hand-edited in $HOME: history lacks it, so no older
#    position explains the content — it must be protected like any other edit.
setup
main_from new.conf 'new
'
printf 'MINE\n' >"$T/new.conf"
guard
expect_out "new tracked file, local edit protected" 'new\.conf'
[ "$(cat "$T/new.conf")" = MINE ] && ok "new file edit survives" || bad "new file edit was clobbered"

# 5. Stale edit worktree: main was committed in $HOME while the edit tree sat
#    still, so its files describe the main before that commit; one local edit on
#    top does not make it safe. Committing here records main~1 as the tree and
#    reverts the $HOME-side commit (4d4fb86).
setup
main_from a.conf 'a2
' sub/b.conf 'b2
'
# The edit tree never pulled: it still holds main~1, plus one local edit on top.
wt checkout -q "$(git --git-dir="$T/.local/share/dotfiles/bare" rev-parse main~1)" -- .
wt reset -q      # the index must describe the files that are now on disk
printf 'c-next\n' >"$WTDIR/sub/c.conf"
guard
expect_exit "stale edit tree" 0
expect_out "stale edit tree is called stale" 'worktree/ \(edit tree\) is only STALE'
expect_no_out "stale edit tree not called uncommitted" 'has uncommitted changes'

# 5a. The same stale tree, reached by a real commit: an edit made in the edit
#     tree and committed there leaves HEAD on main~1 with a clean work tree, so
#     the guard must read the TREE, not the files. A per-file check cannot see
#     this -- each file individually differs from every position of main -- and
#     committing from that state reverts the $HOME-side commit, which is 4d4fb86.
setup
main_from a.conf 'a2
' sub/b.conf 'b2
'
# Sit on main~1 and commit an edit there: HEAD^{tree} is now "older main + edit".
wt reset -q --hard "$(git --git-dir="$T/.local/share/dotfiles/bare" rev-parse main~1)"
printf 'c-next\n' >"$WTDIR/sub/c.conf"
wt commit -qam "edit made before main moved"
# One more uncommitted edit, so the tree is dirty and the stale branch is what
# decides -- a clean tree on an old main is only "behind", which is its own case.
printf 'd-next\n' >"$WTDIR/d.txt"
guard
expect_exit "committed-on-old-main edit tree" 0
expect_out "committed-on-old-main is called stale" 'worktree/ \(edit tree\) is only STALE'
expect_no_out "committed-on-old-main not called merely behind" 'behind main -- sync it'

# 5b. Edit worktree left unchanged while main moved: nothing local, just behind —
#     sync, not "commit or stash".
setup
main_from a.conf 'a2
' sub/b.conf 'b2
'
guard
expect_exit "unchanged edit tree" 0
expect_out "unchanged edit tree is called behind" 'worktree/ \(edit tree\) is behind main'
expect_no_out "unchanged edit tree not called stale" 'only STALE'
expect_no_out "unchanged edit tree not called uncommitted" 'has uncommitted changes'

# 5c. A SIBLING commit (not an ancestor) sharing main's tree must not make a
#     plain edit look stale. Two commits can carry identical trees -- a revert
#     lands exactly there -- and the old check matched any position with that
#     tree, main's own excluded, so an ordinary edit on current main got flagged.
setup
# main: a1 -> (revert) a1, with the reverted commit still a sibling on the reflog.
printf 'a2\n' >"$T/a.conf"
g commit -qam "change"
g revert --no-edit HEAD >/dev/null
git --git-dir="$T/.local/share/dotfiles/bare" --work-tree="$T/bump" checkout -q -f main
wt reset -q --hard "$(git --git-dir="$T/.local/share/dotfiles/bare" rev-parse main)"
printf 'c-next\n' >"$WTDIR/sub/c.conf"
guard
expect_out "edit on current main is uncommitted work" 'worktree/ \(edit tree\) has uncommitted changes'
expect_no_out "edit on current main is not stale" 'only STALE'
# A dirty edit tree does not block a build, and must not read as though it does:
# `nr` was cancelled at this line once, on a run that would have worked.
expect_out "a dirty edit tree is a note, not a warning" '^nr: note: worktree/'
expect_no_out "a dirty edit tree does not say WARNING" 'nr: WARNING worktree/'
expect_out "a dirty edit tree says the run is unaffected" 'this run does not use it'
expect_out "the run ends with a verdict" 'nr: continuing -- nothing above blocks this build'

# 5d. The real accismus layout: the edit worktree shares main's ref (it has no
#     `edit` branch), so a $HOME-side commit moves HEAD without touching the
#     worktree. Its index still describes the earlier main, so git shows the
#     bump as staged reverts. That is staleness, not a change -- sync, don't
#     commit.
setup
main_from a.conf 'a2
' sub/b.conf 'b2
'
wt checkout -q --detach "$(git --git-dir="$T/.local/share/dotfiles/bare" rev-parse main)"
wt checkout -q "$(git --git-dir="$T/.local/share/dotfiles/bare" rev-parse main~1)" -- .
guard
expect_exit "stale index" 0
expect_out "stale index is called stale" 'worktree/ \(edit tree\) is only STALE'
expect_no_out "stale index not called uncommitted" 'has uncommitted changes'

# 5e. Detached at main with a real edit is ordinary work, not staleness.
setup
wt checkout -q --detach "$(git --git-dir="$T/.local/share/dotfiles/bare" rev-parse main)"
printf 'c-next\n' >"$WTDIR/sub/c.conf"
guard
expect_out "detached real edit is uncommitted work" 'worktree/ \(edit tree\) has uncommitted changes'
expect_no_out "detached real edit is not stale" 'only STALE'

# 6. Edit worktree at main with a tracked file edited: real work of its own.
setup
printf 'c-next\n' >"$WTDIR/sub/c.conf"
guard
expect_out "tracked edit in the edit tree is noted" 'worktree/ \(edit tree\) has uncommitted changes'
expect_no_out "tracked edit not called stale" 'only STALE'

# 7. Edit worktree behind main.
setup
main_from a.conf 'a2
'
guard
expect_out "behind edit tree is noted" 'worktree/ \(edit tree\) is behind main'

# 8. No dotfiles repo at all: nothing to guard, and it says so rather than
#    letting a path-resolution failure disable the guards silently.
rm -rf "$T"
mkdir -p "$T"
guard
expect_exit "no repo" 0
expect_out "no repo is announced" 'no dotfiles repo at .* -- skipping the checkout guards'

# 8. An interrupted --update's own files are undone before $HOME is judged, and
#    the guard does it rather than the `nr` function: the guard is executed by
#    path on every run, so it is always the applied copy. On 2026-11-20 a re-run
#    skipped the recovery because the shell held an older `nr` definition.
setup
mkdir -p "$T/bin"
printf '#!/bin/sh\ntouch %s\n' "$T/recovered" >"$T/bin/nr-update-recover"
chmod +x "$T/bin/nr-update-recover"
guard
expect_exit "recovery does not disturb the verdict" 0
[ -f "$T/recovered" ] && ok "the guard runs nr-update-recover" || bad "recovery was not run"
# And its absence is not an error: a $HOME predating the script still guards.
setup
guard
expect_exit "no recovery script is not an error" 0

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
