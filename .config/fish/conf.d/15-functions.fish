function ls
    if command --query lsd
        lsd --hyperlink=auto $argv
    else if command --query colorls
        colorls -G $argv
    else
        command ls -G $argv
    end
end

function e --description "shortcut to the default editor"
    if command --query fzf; and test (count $argv) -eq 0
        set -l file (fzf)
        test -n "$file"; and $EDITOR "$file"
    else
        $EDITOR $argv
    end
end

function tree --description "ls in tree format"
    if command --query lsd
        lsd --tree $argv
    else
        command tree $argv
    end
end

function angband --description "ASCII dungeon crawl game"
    command angband -mgcu \
        -duser=~/.config/angband \
        -dscores=~/Documents/Angband/scores \
        -dsave=~/Documents/Angband/save \
        -dpanic=~/Documents/Angband/panic \
        -darchive=~/Documents/Angband/archive \
        $argv -- -n1
end

function tping
    if command --query ts
        command ping $argv | ts '%Y-%m-%d %H:%M:%S'
    else
        command ping $argv | while read pong
            echo (date "+%Y-%m-%d %H:%M"): $pong
        end
    end
end

function nr-unpin-check --description "deprecated — forwarded to nr-pins check"
    # Superseded by `nr-pins` (.config/nix/nr-pins), which drives everything from
    # the pin registry .config/nix/flake-pins.json and renders the pin block in
    # flake.nix from it, instead of the hand-written spec table that used to
    # live here. The old table hardcoded both the inputs and the packages they
    # were pinned for; the registry generalises that (any number of pins, any
    # package names) and is written by `nr --update` itself when a build fails.
    #
    # Kept as a one-line forwarder so an already-running `nr`, or a shell with
    # this function still loaded, behaves identically.
    bash $HOME/.config/nix/nr-pins check
end

function nr
    # Run in the foreground when invoked interactively (output streams live
    # to the terminal). When invoked non-interactively (agents, scripts,
    # cron), re-exec inside a named tmux session so the full build output
    # survives and can be inspected afterwards.
    if not status is-interactive; and not set -q TMUX; and not set -q NR_TMUX_GUARD
        set -x NR_TMUX_GUARD 1
        set -l _nr_cmd "nr $argv"
        tmux new-session -d -s nr-build "fish -c '$_nr_cmd'"
        echo "nr: started in tmux session 'nr-build'"
        echo "nr: attach with:  tmux attach -t nr-build"
        echo "nr: peek with:    tmux capture-pane -e -t nr-build -p | tail -30"
        return 0
    end
    command mkdir -p $HOME/.cache/nr
    # ---- keep the apply checkout current, then guard the edit tree ----------
    # $HOME is where `nr` builds, so bring it up to `main` first — the apply step
    # (`config checkout main -- :/`), done for you. Silent when in sync. Refuses
    # to touch a $HOME with local edits (that would clobber them).
    # Resolve the dotfiles git dir by existence, the same way the `config` alias
    # in 10-aliases.fish does. `nr` must NOT go through that alias: an alias is
    # fixed when the shell starts, so a session older than a layout change keeps
    # pointing at the old path — and `nr --update`'s commit/push step would then
    # die with "fatal: not a git repository: ~/.local/share/dotfiles/".
    set -l _nr_git $HOME/.local/share/dotfiles
    if test -d $_nr_git/bare
        set _nr_git $_nr_git/bare
    else if not test -d $_nr_git
        set _nr_git $HOME/.config/dotfiles
    end
    if test -d $_nr_git
        set -l _nr_state (git --git-dir=$_nr_git --work-tree=$HOME status --porcelain --untracked-files=no 2>/dev/null)
        if test -n "$_nr_state"
            # Paths an apply would change: compare the work tree with main,
            # ignoring the index (the two checkouts share history, not an index).
            # A path that is missing from $HOME has no local content to lose.
            set -l _nr_paths
            set -l _nr_present
            for _nr_p in (git --git-dir=$_nr_git --work-tree=$HOME diff --name-only main 2>/dev/null)
                set -a _nr_paths $_nr_p
                if test -e $HOME/$_nr_p
                    set -a _nr_present $_nr_p
                end
            end
            # Applying is safe only while every one of those present paths still
            # holds an OLDER committed state: its content matches a position main
            # held before. Anything else is local work that `nr` must not throw
            # away — an `nr --update` retry leaves precisely that, and a leftover
            # hand-edit should be looked at, not replaced.
            # `-C $HOME` matters: a relative pathspec is resolved against the cwd,
            # so from anywhere else these comparisons would match nothing and look
            # "stale" (docs/learnings/2026-10-23-work-tree-does-not-scope-pathspecs.md).
            set -l _nr_stale no
            if test -z "$_nr_present"
                set _nr_stale yes
            else
                for _nr_c in (git --git-dir=$_nr_git reflog show --format=%H main 2>/dev/null | head -25)
                    if git -C $HOME --git-dir=$_nr_git --work-tree=$HOME diff --quiet $_nr_c -- $_nr_present 2>/dev/null
                        set _nr_stale yes
                        break
                    end
                end
            end
            if test "$_nr_stale" = yes
                # `:/` is anchored at the top of the work tree, so this works from
                # any cwd — a bare `.` is resolved against the cwd, which is why
                # the hand-typed form used to want `cd ~`.
                echo "nr: applying "(git --git-dir=$_nr_git rev-parse --short main)" to $HOME"
                if not git --git-dir=$_nr_git --work-tree=$HOME checkout main -- ':/' >$HOME/.cache/nr/apply.log 2>&1
                    echo "nr: ERROR could not apply main to $HOME — refusing to build:" >&2
                    cat $HOME/.cache/nr/apply.log >&2
                    return 1
                end
            else
                # Never clobber. Name the paths whose content exists nowhere in
                # history — those are the local edits — and build what is there:
                # an `nr --update` retry has to rebuild the uncommitted bumps it
                # just left in $HOME, so stopping here would deadlock that path.
                echo "nr: WARNING $HOME has local edits to tracked files — not applying main:" >&2
                set -l _nr_cands (git --git-dir=$_nr_git reflog show --format=%H main 2>/dev/null | head -25)
                set -l _nr_shown 0
                for _nr_p in $_nr_present
                    set -l _nr_hit no
                    for _nr_c in $_nr_cands
                        if git -C $HOME --git-dir=$_nr_git --work-tree=$HOME diff --quiet $_nr_c -- $_nr_p 2>/dev/null
                            set _nr_hit yes
                            break
                        end
                    end
                    if test $_nr_hit = no
                        echo "nr:           $_nr_p" >&2
                        set _nr_shown (math $_nr_shown + 1)
                        test $_nr_shown -ge 8; and break
                    end
                end
                echo "nr:           building what is there; to discard them: cd ~; and config checkout main -- :/" >&2
            end
        end
    end
    # Edit target: ~/.local/share/dotfiles/worktree is where edits are made. It
    # rots silently (the old live/ worktree reached 69 staged files behind main),
    # so say so when it differs from main — either real edits, or a stale tree
    # left over from a commit made in $HOME (e.g. by `nr --update`).
    set -l _nr_wt $HOME/.local/share/dotfiles/worktree
    if test -d $_nr_wt; and test -d $_nr_git
        set -l _nr_wt_head (git -C $_nr_wt rev-parse HEAD 2>/dev/null)
        set -l _nr_main (git --git-dir=$_nr_git rev-parse main 2>/dev/null)
        if test -n "$(git -C $_nr_wt status --porcelain --untracked-files=no 2>/dev/null)"
            # Real edits, or just an older state of main? If the checkout's FILES
            # match some earlier position of main, nothing here is new work — the
            # tree is only stale, which is what `nr --update` leaves behind when it
            # commits in $HOME. Committing in that state reverts that commit
            # (4d4fb86 did exactly that, silently).
            set -l _nr_wt_stale no
            set -l _nr_cands (git --git-dir=$_nr_git reflog show --format=%H main 2>/dev/null)
            for _nr_n in 1 2 3 4 5 6 7 8
                set -a _nr_cands (git --git-dir=$_nr_git rev-parse --verify --quiet "main~$_nr_n" 2>/dev/null)
            end
            for _nr_c in $_nr_cands
                if test -n "$_nr_c"; and test "$_nr_c" != "$_nr_main"; and git -C $_nr_wt diff --quiet $_nr_c 2>/dev/null
                    set _nr_wt_stale yes
                    break
                end
            end
            if test "$_nr_wt_stale" = yes
                echo "nr: WARNING worktree/ (edit tree) is only STALE — its files match an earlier main." >&2
                echo "nr:           Do not commit here (that reverts the $HOME-side commit). Sync: git -C $_nr_wt reset --hard main" >&2
            else
                echo "nr: WARNING worktree/ (edit tree) has uncommitted changes — commit or stash them" >&2
                echo "nr:           (a plain 'reset --hard main' would discard them)" >&2
            end
        else if test -n "$_nr_wt_head"; and test "$_nr_wt_head" != "$_nr_main"
            echo "nr: WARNING worktree/ (edit tree) is behind main — sync it: git -C $_nr_wt pull --ff-only" >&2
        end
    end
    # (A) tee log: build output truncates last.log, switch output appends.
    set -l _nr_log $HOME/.cache/nr/last.log
    set -l _nr_old_system
    set -l _nr_new_system
    set -l _nr_update no
    set -l _nr_args
    set -l _nr_inputs
    set -l _nr_switch_ok 0
    set -l _nr_unpinned no
    if test "$_os" = darwin
        set _nr_old_system (command readlink -f /nix/var/nix/profiles/system 2>/dev/null)
    else
        set _nr_old_system (command readlink -f /run/current-system 2>/dev/null)
    end
    # Peel off nr-specific flags. --update and -U/--update-input are handled
    # here (update scripts + `nix flake update`); everything else is passed
    # through to darwin-rebuild / nixos-rebuild.
    set -l i 1
    while test $i -le (count $argv)
        switch "$argv[$i]"
            case --update
                set _nr_update yes
            case -U --update-input
                set -l _nr_input $argv[(math $i + 1)]
                if test -z "$_nr_input"
                    echo "nr: $argv[$i] requires an input name" >&2
                    return 1
                end
                set -a _nr_inputs $_nr_input
                set i (math $i + 1)
            case '*'
                set -a _nr_args $argv[$i]
        end
        set i (math $i + 1)
    end
    if test "$_nr_update" = yes
        # pi is a rev-pinned flake input; follow its GitHub releases.
        set -l _pwd $PWD
        cd $HOME/.config/nix
        bash pkgs/pi/update.sh
        # swival vendors its own wheel set (both platforms) from upstream's
        # uv.lock, so its bump is platform-independent — same place as pi.
        bash pkgs/swival/update.sh
        cd $_pwd
        if test "$_os" = darwin
            set -l _pwd $PWD
            cd $HOME/.config/nix
            bash pkgs/oxillama/update.sh
            bash modules/overlays/zen-browser/update.sh
            bash modules/overlays/opencode/update.sh
            bash modules/overlays/daisydisk-overlay/update.sh
            bash modules/overlays/osaurus/update.sh
            bash modules/overlays/openfang/update.sh
            bash modules/overlays/ghostty/update.sh
            bash modules/overlays/orca-ade/update.sh
            alejandra pkgs/oxillama/default.nix modules/overlays/opencode/default.nix modules/overlays/daisydisk-overlay/default.nix modules/overlays/osaurus/default.nix modules/overlays/openfang/default.nix modules/overlays/ghostty/default.nix modules/overlays/orca-ade/default.nix
            cd $_pwd
        else
            set -l _pwd $PWD
            cd $HOME/.config/nix
            bash pkgs/bedrock-server/update.sh
            bash pkgs/rsync-tmbackup/update.sh
            alejandra pkgs/bedrock-server/default.nix pkgs/rsync-tmbackup/default.nix
            cd $_pwd
        end
    end
    # Refresh flake inputs as the invoking user (never as root, so flake.lock
    # stays owned by scott), then switch with direct sudo/doas elevation.
    if test "$_nr_update" = yes; or set -q _nr_inputs[1]
        set -l _pwd $PWD
        cd $HOME/.config/nix
        if test "$_nr_update" = yes
            # Self-expiring flake input pins. `nr-pins` (.config/nix/nr-pins)
            # owns the registry .config/nix/flake-pins.json and renders the
            # delimited pin block in flake.nix from it.
            #   snapshot — remember the revs that build right now, so a failed
            #              update can pin the culprit back to the last rev that
            #              worked
            #   check    — probe each existing pin against its branch head and
            #              drop the ones whose blocker has cleared, so pins
            #              expire on their own
            # The other half — CREATING a pin when an update breaks the build —
            # runs in the retry loop below.
            bash $HOME/.config/nix/nr-pins snapshot
            if test $status -ne 0
                echo "nr: WARNING — could not snapshot the current input revs;" >&2
                echo "    if this update breaks the build, the culprit cannot be pinned back." >&2
            end
            bash $HOME/.config/nix/nr-pins check
            if test $status -eq 2
                set _nr_unpinned yes
            end
            nix flake update
        else
            nix flake update $_nr_inputs
        end
        cd $_pwd
    end
    # NOTE: a build failure during --update is triaged automatically (see the
    # retry loop below). Two things get undone without asking:
    #   - a flake input whose branch head would force a from-source build
    #     (`nr-pins` pins it back to the snapshot rev), and
    #   - a prebuilt-overlay bump whose package is the failing derivation
    #     (`nr-pins` restores that overlay directory from git — the last
    #     committed pin).
    # Anything else — our own modules, a stale FOD hash, an eval error — is left
    # alone: fix it by hand.
    # Split build from activation, each as its least-privileged user:
    #   1. `nh build` — full nh/nix-output-monitor output (pretty bars,
    #      eval/build) running as scott. NEVER as root: build hooks and
    #      provider flags would all run privileged.
    #   2. exact-path sudo/doas switch — same cached build, only the
    #      profile-set + activation step elevates. Matches the scoped
    #      NOPASSWD/noPass rules (nh can't be scoped safely: it wraps
    #      elevated commands in `sudo env … <cmd>`).
    # `darwin-rebuild`/`nixos-rebuild` re-use nh's cached build, so the
    # switch phase is near-instant.
    set -l _nr_pinned no
    set -l _nr_reverted no
    set -l _nr_verify_failed no
    set -l _nr_attempt 0
    set -l _nr_build_ok 1
    while true
        set _nr_attempt (math $_nr_attempt + 1)
        if test "$_os" = darwin
            nh darwin build $HOME/.config/nix $_nr_args 2>&1 | tee $_nr_log
            set _nr_build_ok $pipestatus[1]
        else
            nh os build $HOME/.config/nix $_nr_args 2>&1 | tee $_nr_log
            set _nr_build_ok $pipestatus[1]
        end
        if test $_nr_build_ok -eq 0
            # The build succeeded. Smoke-test the prebuilt packages it produced
            # before switching to them: a release can build and still be broken
            # (won't start, wrong payload, broken code signature, a config the
            # new binary rejects). `nr-pins verify` runs each overlay's optional
            # verify.sh against the freshly built store path and, on failure,
            # reverts that bump the same way diagnose undoes a failed build — so
            # exit 3 means "rebuild with the last-good pin".
            #
            # The new system path comes from nh's own output (`>>> /nix/store/…`)
            # in the log we already tee. A no-change build prints no such line,
            # and then there is nothing new to verify.
            set -l _nr_sys (grep -oE '/nix/store/[a-z0-9]{32}-(darwin|nixos)-system[0-9A-Za-z._-]*' $_nr_log 2>/dev/null | tail -1)
            if test -n "$_nr_sys"
                bash $HOME/.config/nix/nr-pins verify $_nr_sys
                set -l _nr_verify $status
                if test $_nr_verify -eq 3
                    set _nr_reverted yes
                    echo "nr: a package failed its smoke test — rolled back to its last-good pin, rebuilding"
                    continue
                else if test $_nr_verify -ne 0
                    echo "nr: a package failed its smoke test and could not be rolled back; not switching" >&2
                    set _nr_verify_failed yes
                    set _nr_build_ok 1
                    break
                end
            end
            break
        end
        # The build failed. If this run updated the inputs, ask nr-pins whether
        # the failure is a regression it can undo: it reads the failing
        # derivation out of the log and either
        #   - restores a prebuilt-overlay directory whose just-bumped package is
        #     the failing derivation (git checkout of the last committed pin), or
        #   - for each nixpkgs-family input that moved, probes whether that
        #     input's branch head would have to BUILD the failing package from
        #     source; if so it pins the input back to the snapshot rev (the last
        #     rev that worked).
        # Either way we rebuild. A failure that neither explains — i.e. our own
        # code — is never touched. Bounded, so an undo that does not actually
        # help cannot loop forever.
        if test "$_nr_update" = yes; and test $_nr_attempt -lt 3
            bash $HOME/.config/nix/nr-pins diagnose $_nr_log
            set -l _nr_diag $status
            # 2 = an input was pinned (registry + flake.nix changed);
            # 3 = an overlay bump was reverted (working tree restored, no
            #     registry change). Both mean "rebuild"; the commit message
            #     below has to say which actually happened.
            if test $_nr_diag -eq 2 -o $_nr_diag -eq 3
                if test $_nr_diag -eq 3
                    set _nr_reverted yes
                else
                    set _nr_pinned yes
                end
                echo "nr: rolled a dependency back to its last-good pin — rebuilding"
                continue
            end
        end
        break
    end
    if test $_nr_build_ok -eq 0
        if test "$_os" = darwin
            sudo /run/current-system/sw/bin/darwin-rebuild switch --flake $HOME/.config/nix $_nr_args 2>&1 | tee -a $_nr_log
            set _nr_switch_ok $pipestatus[1]
        else
            doas /run/current-system/sw/bin/nixos-rebuild switch --flake $HOME/.config/nix $_nr_args 2>&1 | tee -a $_nr_log
            set _nr_switch_ok $pipestatus[1]
        end
    else
        # Build failed — treat as a failed switch (skips commit/push)
        set _nr_switch_ok 1
    end
    if test "$_nr_update" = yes; and test "$_nr_switch_ok" -eq 0
        # Commit the version bumps the update scripts + nh generated, then push.
        # Deliberately staged in the APPLY tree: $HOME is both $_nr_git's work
        # tree and the tree the update scripts wrote and `nh` just
        # verified, so this commits what was built and verified — never whatever
        # happens to be checked out for editing in ~/.local/share/dotfiles/worktree.
        # Every call below spells out --git-dir/--work-tree from $_nr_git rather
        # than using the `config` alias: the alias is frozen when the shell
        # starts, so a session older than a git-dir move would aim these at the
        # old path ("fatal: not a git repository").
        # Paths stay $HOME-absolute so the block is cwd-independent (--work-tree
        # does not scope pathspecs, and a path outside the work tree is refused).
        # The pin registry and the pin engine ride along, so a pin that nr-pins
        # added or dropped this run is committed and pushed with the bump.
        # Guarded: `git add` fails the whole pathspec list if one path is
        # missing (e.g. a machine whose work tree predates the file).
        set -l _nr_files $HOME/.config/nix/flake.lock
        for _nr_f in $HOME/.config/nix/flake-pins.json $HOME/.config/nix/nr-pins
            if test -e $_nr_f
                set -a _nr_files $_nr_f
            end
        end
        # Include flake.nix when it changed — it carries the rendered pin block.
        if not git --git-dir=$_nr_git --work-tree=$HOME diff --quiet -- $HOME/.config/nix/flake.nix
            set -a _nr_files $HOME/.config/nix/flake.nix
        end
        if test "$_os" = darwin
            set -a _nr_files \
                $HOME/.config/nix/pkgs/oxillama/default.nix \
                $HOME/.config/nix/modules/overlays/zen-browser/sources.json \
                $HOME/.config/nix/modules/overlays/opencode/default.nix \
                $HOME/.config/nix/modules/overlays/daisydisk-overlay/default.nix \
                $HOME/.config/nix/modules/overlays/osaurus/default.nix \
                $HOME/.config/nix/modules/overlays/openfang/default.nix \
                $HOME/.config/nix/modules/overlays/ghostty/default.nix \
                $HOME/.config/nix/modules/overlays/orca-ade/default.nix
        else
            set -a _nr_files \
                $HOME/.config/nix/pkgs/bedrock-server/default.nix \
                $HOME/.config/nix/pkgs/rsync-tmbackup/default.nix
        end
        git --git-dir=$_nr_git --work-tree=$HOME add $_nr_files
        if git --git-dir=$_nr_git --work-tree=$HOME diff --cached --quiet
            echo "nr: no dependency bumps to commit"
        else
            set -l _nr_msg "nr --update: bump nightly dependency versions"
            if test "$_nr_pinned" = yes
                set _nr_msg "nr --update: pin a nixpkgs input to its last-good rev + bump nightly dependency versions"
            else if test "$_nr_unpinned" = yes
                set _nr_msg "nr --update: drop temporary nixpkgs pin(s) + bump nightly dependency versions"
            else if test "$_nr_reverted" = yes
                set _nr_msg "nr --update: keep the last-good pin for a bad dependency bump + bump nightly dependency versions"
            end
            git --git-dir=$_nr_git --work-tree=$HOME commit -m "$_nr_msg"
            if test "$_os" = darwin
                git --git-dir=$_nr_git --work-tree=$HOME push origin
                git --git-dir=$_nr_git --work-tree=$HOME push sophrosyne
            else
                git --git-dir=$_nr_git --work-tree=$HOME push origin
            end
        end
    else if test "$_nr_update" = yes
        if test "$_nr_verify_failed" = yes
            echo "nr: a package failed its smoke test; skipping commit and push"
            echo "nr: working tree has uncommitted bumps — fix or revert that package, then re-run nr"
        else
            echo "nr: nh switch failed (exit $_nr_switch_ok); skipping commit and push"
            echo "nr: working tree has uncommitted bumps — fix the build, then re-run nr"
        end
    end
    if test "$_os" = darwin
        set _nr_new_system (command readlink -f /nix/var/nix/profiles/system 2>/dev/null)
    else
        set _nr_new_system (command readlink -f /run/current-system 2>/dev/null)
    end
    if test "$_nr_old_system" != "$_nr_new_system"; and command --query what-changed
        what-changed "$_nr_old_system" "$_nr_new_system"
    end
end

function hr
    nr $argv
end

function age
    if command --query rage
        rage $argv
    else
        command age $argv
    end
end

function myip
    set -l ip (mylocation 2>/dev/null | jq -r '.ip // empty' 2>/dev/null)
    if test -z "$ip"
        set ip (curl -sf --max-time 5 https://icanhazip.com 2>/dev/null | string trim)
    end
    if test -z "$ip"
        echo "Could not determine IP" >&2
        return 1
    end
    echo "$ip"
end

function myweather
    set -l json (mylocation 2>/dev/null)
    set -l loc (echo "$json" | jq -r '.loc // empty' 2>/dev/null)
    if test -z "$loc"
        echo "Could not determine location (ipinfo.io rate limited?)" >&2
        return 1
    end
    set -l city (echo "$json" | jq -r '.city // empty' 2>/dev/null)
    set -l region (echo "$json" | jq -r '.region // empty' 2>/dev/null)
    if test -n "$city"
        echo
        echo "Weather report: $city, $region"
        echo
    end
    curl -s "wttr.in/~$loc?uQ0"
end

function nix-shell
    if contains -- --command $argv; or contains -- --run $argv
        command nix-shell $argv
    else
        command nix-shell --command fish $argv
    end
end
