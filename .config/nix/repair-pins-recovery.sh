#!/usr/bin/env bash
# repair-pins-recovery.sh — recover a $HOME/.config/nix broken by the
# 2026-10-13 nr-pins bug (an emptied pin registry deleted the input
# declarations, so every `inputs.X.follows = "nixpkgs"` dangled).
#
# WHAT BROKE
#   `nr --update` runs `nr-pins snapshot` then `nr-pins check`. That run dropped
#   the last two pins and re-rendered flake.nix's pin block from the now-empty
#   registry. The buggy render_block emitted NOTHING for an empty registry, so
#   the block stopped declaring `nixpkgs` / `nixpkgs-unstable` entirely — while
#   the rest of flake.nix follows them by name:
#
#       error: … while updating the lock file of flake 'path:/Users/scott/.config/nix'
#              error: input 'agenix/nixpkgs' follows a non-existent input 'nixpkgs'
#
#   and `nh darwin build` aborted the same way.
#
# THE FIX
#   render_block now ALWAYS declares every input the registry's `base` list
#   owns — the pinned rev URL while a pin is active, that input's normal branch
#   URL otherwise — so a dropped pin can never remove the declaration again.
#
# RUN THIS ONCE, as scott, on the machine whose $HOME/.config/nix is broken.
# It repairs in place, so the default source is the same tree it repairs:
#
#     bash ~/.config/nix/repair-pins-recovery.sh
#
#   Pass the directory holding the fixed files if they are somewhere else
#   (e.g. a worktree you reviewed the fix in):
#
#     bash repair-pins-recovery.sh ~/src/bonds/dotfiles/.config/nix
#
# It is idempotent, backs up what it replaces, and NEVER activates anything —
# no `nr`, no `darwin-rebuild switch`. Scott runs `nr` himself afterwards.
#
# NOTE: this file IS tracked (.config/nix/repair-pins-recovery.sh). Older
# revisions of this header claimed otherwise — the repo sets
# status.showUntrackedFiles=no, which hides untracked files, but that does not
# apply here. Verify with:
#     git --git-dir=$HOME/.local/share/dotfiles --work-tree=$HOME ls-files .config/nix/repair-pins-recovery.sh
set -euo pipefail

FLAKE_DIR="${HOME}/.config/nix"
FIXED_SRC="${1:-$HOME/.config/nix}"
STAMP="$(date '+%Y%m%d-%H%M%S')"
mkdir -p "$HOME/.cache/nr"
BACKUP="$(mktemp -d "$HOME/.cache/nr/repair-XXXXXX")"   # unique: two runs in the same second must not share one

say() { printf 'repair-pins: %s\n' "$*"; }
die() { printf 'repair-pins: %s\n' "$*" >&2; exit 1; }

[ -f "$FLAKE_DIR/flake.nix" ] || die "no flake.nix at $FLAKE_DIR — is this the right machine?"

# --- locate the fixed engine (the fix is identified by its reg_base function) --
if [ ! -f "$FIXED_SRC/nr-pins" ] || ! grep -q 'reg_base' "$FIXED_SRC/nr-pins"; then
    cat >&2 <<EOF
repair-pins: no FIXED nr-pins found at: $FIXED_SRC

Pass the directory that holds the fixed files, e.g. the worktree the fix was
reviewed in:

    bash $0 ~/src/bonds/dotfiles/.config/nix

Or, once the fix is committed to main, restore the files from git yourself and
re-run this script (this also restores the pinned block):

    git --git-dir=\$HOME/.local/share/dotfiles --work-tree=\$HOME checkout main -- \\
        .config/nix/nr-pins .config/nix/flake-pins.json
EOF
    exit 1
fi

say "fixed engine: $FIXED_SRC/nr-pins"
say "target:       $FLAKE_DIR"

# --- back up what we are about to replace (reversible) ------------------------
for f in flake.nix flake-pins.json nr-pins; do
    [ -e "$FLAKE_DIR/$f" ] && cp -p "$FLAKE_DIR/$f" "$BACKUP/$f"
done
say "backed up the current flake.nix / flake-pins.json / nr-pins to $BACKUP"

# --- install the fixed engine -------------------------------------------------
# The documented fallback (restore the fixed files from git into $HOME, then
# re-run) puts the fix AT the target, so source == target is a normal case: just
# re-render. `install` would fail with "are the same file".
if [ "$FIXED_SRC" -ef "$FLAKE_DIR" ]; then
    say "source dir IS the target dir — skipping the installs, just re-rendering"
else
    install -m 0755 "$FIXED_SRC/nr-pins" "$FLAKE_DIR/nr-pins"
    say "installed the fixed nr-pins"
fi

# --- install the registry when the source carries one with the new `base` list -
# The on-disk registry is the emptied {"pins": []} the failed run left behind.
# The fixed engine handles that (its default `base` still declares the two
# nixpkgs inputs), but restoring the pinned registry also restores the exact
# pre-failure state: flake.lock already records those pinned revs, so flake.nix
# and the lock stay consistent and no input has to be re-fetched.
if [ "$FIXED_SRC" -ef "$FLAKE_DIR" ]; then
    :   # registry is already the fixed one; nothing to install
elif [ -f "$FIXED_SRC/flake-pins.json" ] \
    && jq -e '.base | type == "array" and length > 0' "$FIXED_SRC/flake-pins.json" > /dev/null 2>&1; then
    install -m 0600 "$FIXED_SRC/flake-pins.json" "$FLAKE_DIR/flake-pins.json"
    say "installed the registry from $FIXED_SRC/flake-pins.json ($(jq -r '.pins | length' "$FLAKE_DIR/flake-pins.json") pin(s), $(jq -r '.base | length' "$FLAKE_DIR/flake-pins.json") base input(s))"
    # The restored pins must already be recorded in flake.lock, or flake.nix would
    # point at revs the lock does not know. Warn loudly (still not fatal: the next
    # `nr --update` re-locks).
    for r in $(jq -r '.pins[] | .url' "$FLAKE_DIR/flake-pins.json" | sed -E 's|.*/||'); do
        jq -e --arg r "$r" '[.nodes[].locked.rev] | index($r) != null' "$FLAKE_DIR/flake.lock" > /dev/null 2>&1 \
            || say "WARNING: pinned rev ${r:0:12} is not in flake.lock — flake.nix will point at a rev the lock lacks"
    done
else
    say "WARNING: no registry with a 'base' list at $FIXED_SRC/flake-pins.json — leaving the on-disk registry in place"
    say "         (the fixed engine defaults 'base' to nixpkgs + nixpkgs-unstable, so the block will still be valid)"
fi

# --- re-render the pin block --------------------------------------------------
NR_PINS_FLAKE_DIR="$FLAKE_DIR" bash "$FLAKE_DIR/nr-pins" apply \
    || die "the pin block was not re-rendered — the tree is now HALF-REPAIRED (new nr-pins/registry, old flake.nix). Restore $BACKUP/flake.nix and re-run."
say "re-rendered the pin block"
sed -n '/BEGIN nr-managed input pins/,/END nr-managed input pins/p' "$FLAKE_DIR/flake.nix" \
    | grep -E '\.url =' | sed 's/^/           /'

# --- verify (never activates anything) ----------------------------------------
nix-instantiate --parse "$FLAKE_DIR/flake.nix" > /dev/null \
    || die "the rewritten flake.nix does not parse — restore $BACKUP/flake.nix"
say "flake.nix parses (nix-instantiate --parse)"

# MANDATORY: this is the check that actually catches the bug — `--parse` is blind
# to a dangling `follows`, but resolving the inputs reproduces the exact incident
# ("input 'agenix/nixpkgs' follows a non-existent input 'nixpkgs'") on a broken
# tree and passes on a repaired one. `--no-write-lock-file` guarantees it cannot
# touch flake.lock. Caveat: nix resolves nested `follows` lazily, so this is
# reliable for the real git-input flake, less so for a toy `path:`-input flake.
nix flake metadata --no-write-lock-file "$FLAKE_DIR" > /dev/null \
    || die "flake inputs still do not resolve — restore $BACKUP/flake.nix"
say "flake inputs resolve (nix flake metadata --no-write-lock-file)"

# Best effort: prove the flake evaluates again. Needs the lock to be in sync and
# the inputs available; skip with a note if that is not possible offline.
attr=""
for kind in darwinConfigurations nixosConfigurations; do
    name="$( (cd "$FLAKE_DIR" && nix eval --json --apply 'builtins.attrNames' ".#$kind" 2> /dev/null) \
        | jq -r 'if length == 1 then .[0] else empty end' 2> /dev/null || true)"
    [ -n "$name" ] && { attr="$kind.$name.system"; break; }
done
if [ -n "$attr" ]; then
    if out="$( (cd "$FLAKE_DIR" && nix eval ".#$attr.drvPath" --raw) 2>&1 )"; then
        say "flake evaluates: $attr.drvPath → $(printf '%s\n' "$out" | tail -1)"
    else
        say "NOTE: could not evaluate .#$attr.drvPath yet —"
        printf '%s\n' "$out" | tail -5 | sed 's/^/           /'
        say "      (offline / lock out of date is not a failure of this repair; run 'nr --update' next)"
    fi
else
    say "NOTE: could not resolve a system attribute to evaluate — skipping the eval check"
fi

cat <<EOF

Done. Nothing was activated.
Backup of what was replaced: $BACKUP

Next, in your own shell:
    nr          # or: nr --update   — the pin mechanism now keeps the declarations

EOF
