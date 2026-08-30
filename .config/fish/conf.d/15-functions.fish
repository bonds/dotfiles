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

function nr
    # On linux, if not already inside tmux, re-exec inside a named session
    # so the full build output is visible via `tmux attach -t nr-build`.
    if test "$_os" != darwin; and not set -q TMUX; and not set -q NR_TMUX_GUARD
        set -x NR_TMUX_GUARD 1
        set -l _nr_cmd "nr $argv"
        tmux new-session -d -s nr-build "fish -c '$_nr_cmd'"
        echo "nr: started in tmux session 'nr-build'"
        echo "nr: attach with:  tmux attach -t nr-build"
        echo "nr: peek with:    tmux capture-pane -e -t nr-build -p | tail -30"
        return 0
    end
    set -l _nr_old_system
    set -l _nr_new_system
    set -l _nr_update no
    set -l _nr_args
    set -l _nr_inputs
    set -l _nr_switch_ok 0
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
            alejandra pkgs/oxillama/default.nix modules/overlays/zen-browser/default.nix modules/overlays/opencode/default.nix modules/overlays/daisydisk-overlay/default.nix modules/overlays/osaurus/default.nix modules/overlays/openfang/default.nix
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
            nix flake update
        else
            nix flake update $_nr_inputs
        end
        cd $_pwd
    end
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
    if test "$_os" = darwin
        nh darwin build $HOME/.config/nix $_nr_args
        set _nr_build_ok $status
        if test $_nr_build_ok -eq 0
            sudo /run/current-system/sw/bin/darwin-rebuild switch --flake $HOME/.config/nix $_nr_args
            set _nr_switch_ok $status
        else
            # Build failed — treat as a failed switch (skips commit/push)
            set _nr_switch_ok 1
        end
    else
        nh os build $HOME/.config/nix $_nr_args
        set _nr_build_ok $status
        if test $_nr_build_ok -eq 0
            doas /run/current-system/sw/bin/nixos-rebuild switch --flake $HOME/.config/nix $_nr_args
            set _nr_switch_ok $status
        else
            set _nr_switch_ok 1
        end
    end
    if test "$_nr_update" = yes; and test "$_nr_switch_ok" -eq 0
        # Commit the version bumps the update scripts + nh generated, then push.
        # Use home-absolute pathspecs so this block is cwd-independent
        # (running `nr --update` from ~/.config/nix would otherwise make
        # git resolve `.config/nix/...` against the cwd and fail the add).
        set -l _nr_files $HOME/.config/nix/flake.lock
        if test "$_os" = darwin
            set -a _nr_files \
                $HOME/.config/nix/pkgs/oxillama/default.nix \
                $HOME/.config/nix/modules/overlays/zen-browser/default.nix \
                $HOME/.config/nix/modules/overlays/opencode/default.nix \
                $HOME/.config/nix/modules/overlays/daisydisk-overlay/default.nix \
                $HOME/.config/nix/modules/overlays/osaurus/default.nix \
                $HOME/.config/nix/modules/overlays/openfang/default.nix
        else
            set -a _nr_files \
                $HOME/.config/nix/pkgs/bedrock-server/default.nix \
                $HOME/.config/nix/pkgs/rsync-tmbackup/default.nix
        end
        config add $_nr_files
        if config diff --cached --quiet
            echo "nr: no dependency bumps to commit"
        else
            config commit -m "nr --update: bump nightly dependency versions"
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
    nice home-manager switch --flake ~/.config/nix $argv
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
