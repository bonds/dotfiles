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
    # NOTE: a build failure during --update is now triaged automatically (see
    # the retry loop below). A failure that is NOT an input regression — our
    # own modules, a stale FOD hash in modules/packages/, … — is left alone:
    # revert flake.lock + the overlay files and fix it by hand.
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
            break
        end
        # The build failed. If this run updated the inputs, ask nr-pins whether
        # the failure is an input regression: it reads the failing derivation
        # out of the log and, for each nixpkgs-family input that moved, probes
        # whether that input's branch head would have to BUILD the failing
        # package from source. If so it pins the input back to the snapshot rev
        # (the last rev that worked) and we rebuild. A failure that no nixpkgs
        # input explains — i.e. our own code — is never pinned. Bounded, so a
        # pin that does not actually help cannot loop forever.
        if test "$_nr_update" = yes; and test $_nr_attempt -lt 3
            bash $HOME/.config/nix/nr-pins diagnose $_nr_log
            if test $status -eq 2
                set _nr_pinned yes
                echo "nr: an input was pinned to its last-good rev — rebuilding"
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
        # Use home-absolute pathspecs so this block is cwd-independent
        # (running `nr --update` from ~/.config/nix would otherwise make
        # git resolve `.config/nix/...` against the cwd and fail the add).
        # The pin registry and the pin engine ride along, so a pin that nr-pins
        # added or dropped this run is committed and pushed with the bump.
        # Guarded: `config add` fails the whole pathspec list if one path is
        # missing (e.g. a machine whose work tree predates the file).
        set -l _nr_files $HOME/.config/nix/flake.lock
        for _nr_f in $HOME/.config/nix/flake-pins.json $HOME/.config/nix/nr-pins
            if test -e $_nr_f
                set -a _nr_files $_nr_f
            end
        end
        # Include flake.nix when it changed — it carries the rendered pin block.
        if not config diff --quiet -- $HOME/.config/nix/flake.nix
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
        config add $_nr_files
        if config diff --cached --quiet
            echo "nr: no dependency bumps to commit"
        else
            set -l _nr_msg "nr --update: bump nightly dependency versions"
            if test "$_nr_pinned" = yes
                set _nr_msg "nr --update: pin a nixpkgs input to its last-good rev + bump nightly dependency versions"
            else if test "$_nr_unpinned" = yes
                set _nr_msg "nr --update: drop temporary nixpkgs pin(s) + bump nightly dependency versions"
            end
            config commit -m "$_nr_msg"
            if test "$_os" = darwin
                config push origin
                config push sophrosyne
            else
                config push origin
            end
        end
    else if test "$_nr_update" = yes
        echo "nr: nh switch failed (exit $_nr_switch_ok); skipping commit and push"
        echo "nr: working tree has uncommitted bumps — fix the build, then re-run nr"
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
