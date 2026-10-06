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

function __nr_local_builds --argument-names flake_ref
    # Print every output of this lock's full build graph that would have to be
    # COMPILED locally: absent from every substituter (parallel narinfo probe),
    # fixed-output derivations included. This counts the from-scratch
    # requirement of a lock, independent of what is already realised in
    # /nix/store, so a baseline and a post-update measurement are directly
    # comparable. Prints one store path per line; exits non-zero if the
    # measurement cannot be trusted (callers must fail closed).
    set -l tmp (command mktemp -d /tmp/nr-local-builds.XXXXXX)
    or return 1
    set -l drv (timeout 300 nix eval --raw "$flake_ref.drvPath" 2>/dev/null)
    if test $status -ne 0; or test -z "$drv"
        command rm -rf $tmp
        echo "nr: could not evaluate $flake_ref.drvPath" >&2
        return 1
    end
    # FODs are included deliberately: a stale-hash pin (e.g. node-v43.7.7-headers.tar.gz) is neither realised locally nor substitutable, exactly the "download will fail / not cached yet" case the gate must catch.
    timeout 300 nix derivation show -r "$drv" 2>/dev/null \
        | jq -r 'to_entries[].value.outputs[].path' \
        | sort -u >$tmp/paths
    if not test -s $tmp/paths
        command rm -rf $tmp
        echo "nr: could not list build-graph outputs" >&2
        return 1
    end
    set -l subs
    for s in (timeout 30 nix config show substituters 2>/dev/null | string split --no-empty ' ')
        if string match -qr '^https?://' -- $s
            set -a subs (string replace -r '/$' '' -- $s)
        end
    end
    if test (count $subs) -eq 0
        command rm -rf $tmp
        echo "nr: no http substituter configured — cannot measure local builds" >&2
        return 1
    end
    # One narinfo probe per output path per substituter, all in one curl.
    awk -v subs=(string join ' ' $subs) '{
        h = $0; sub(/^\/nix\/store\//, "", h); sub(/-.*/, "", h);
        n = split(subs, S, " ");
        for (i = 1; i <= n; i++) { print "url = " S[i] "/" h ".narinfo"; print "output = /dev/null" }
    }' $tmp/paths >$tmp/cfg
    timeout 300 curl -s -K $tmp/cfg --parallel --parallel-max 64 \
        --retry 2 --retry-delay 1 --retry-all-errors \
        -w '%{http_code} %{url_effective}\n' >$tmp/probe
    set -l curl_ok $status
    set -l npaths (command wc -l <$tmp/paths | string trim)
    set -l nprobe (command wc -l <$tmp/probe | string trim)
    if test $curl_ok -ne 0; or command grep -q '^000 ' $tmp/probe
        command rm -rf $tmp
        echo "nr: narinfo probe had transport errors — refusing to guess a baseline" >&2
        return 1
    end
    set -l nexpected (math "$npaths * "(count $subs))
    if test "$nprobe" != "$nexpected"
        command rm -rf $tmp
        echo "nr: narinfo probe incomplete ($nprobe/$npaths answers) — refusing to guess" >&2
        return 1
    end
    command sed -nE 's/^200 .*\/([a-z0-9]{32})\.narinfo$/\1/p' $tmp/probe | sort -u >$tmp/ok
    if not test -s $tmp/ok
        command rm -rf $tmp
        echo "nr: substituter reports nothing valid — refusing to guess" >&2
        return 1
    end
    command awk 'NR == FNR { ok[$1] = 1; next } {
        h = $0; sub(/^\/nix\/store\//, "", h); sub(/-.*/, "", h);
        if (!(h in ok)) print $0
    }' $tmp/ok $tmp/paths
    set -l rc $status
    command rm -rf $tmp
    return $rc
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
    # (B) baseline-delta gate inputs: where the baseline, the pre-update lock
    # and the system installable for THIS host live.
    set -l _nr_base_file $HOME/.cache/nr/willbuild-baseline
    set -l _nr_prev_lock $HOME/.cache/nr/flake.lock.prev
    set -l _nr_attr nixosConfigurations
    if test "$_os" = darwin
        set _nr_attr darwinConfigurations
    end
    set -l _nr_ref "$HOME/.config/nix#$_nr_attr."(hostname -s)".system"
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
    # (B) Prepare the baseline-delta gate BEFORE touching anything: save the
    # lock so a refused bump can be rolled back, and create the local-build
    # baseline on first use while the current lock is still untouched.
    if test "$_nr_update" = yes; or set -q _nr_inputs[1]
        command cp -p $HOME/.config/nix/flake.lock $_nr_prev_lock
        if not test -s $_nr_base_file
            echo "nr: measuring local-build baseline for the current lock (about a minute)…"
            __nr_local_builds "$_nr_ref" >$_nr_base_file.tmp
            if test $status -ne 0
                command rm -f $_nr_base_file.tmp
                echo "nr: baseline measurement failed — not updating" >&2
                return 1
            end
            command mv $_nr_base_file.tmp $_nr_base_file
            echo "nr: baseline: "(count (command cat $_nr_base_file))" local builds"
        end
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
            nix flake update
        else
            nix flake update $_nr_inputs
        end
        cd $_pwd
    end
    # (B) Baseline-delta gate: REFUSE a bump whose new lock needs MORE locally
    # built derivations than the baseline. The threshold is a baseline DELTA,
    # not an absolute zero — every darwin/nixos closure has host-specific
    # derivations (activation script, system-path, etc.d) that no substituter
    # serves, so a literal 0 would refuse every update.
    if test "$_nr_update" = yes; or set -q _nr_inputs[1]
        set -l _nr_new (__nr_local_builds "$_nr_ref")
        if test $status -ne 0
            command cp -p $_nr_prev_lock $HOME/.config/nix/flake.lock
            echo "nr: could not measure the updated lock — flake.lock restored, nothing built" >&2
            return 1
        end
        set -l _nr_base (command cat $_nr_base_file 2>/dev/null)
        if test (count $_nr_new) -gt (count $_nr_base)
            set -l _nr_extra
            for _nr_p in $_nr_new
                contains -- $_nr_p $_nr_base; or set -a _nr_extra $_nr_p
            end
            command cp -p $_nr_prev_lock $HOME/.config/nix/flake.lock
            echo "nr: REFUSING update: "(count $_nr_new)" local builds vs baseline "(count $_nr_base) >&2
            echo "nr: extra local builds the new lock would require:" >&2
            printf '  %s\n' $_nr_extra[1..40] >&2
            if test (count $_nr_extra) -gt 40
                echo "  … and "(math (count $_nr_extra) - 40)" more" >&2
            end
            echo "nr: flake.lock restored; no build, no activation, no commit" >&2
            return 1
        end
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
        nh darwin build $HOME/.config/nix $_nr_args 2>&1 | tee $_nr_log
        set _nr_build_ok $pipestatus[1]
        if test $_nr_build_ok -eq 0
            sudo /run/current-system/sw/bin/darwin-rebuild switch --flake $HOME/.config/nix $_nr_args 2>&1 | tee -a $_nr_log
            set _nr_switch_ok $pipestatus[1]
        else
            # Build failed — treat as a failed switch (skips commit/push)
            set _nr_switch_ok 1
        end
    else
        nh os build $HOME/.config/nix $_nr_args 2>&1 | tee $_nr_log
        set _nr_build_ok $pipestatus[1]
        if test $_nr_build_ok -eq 0
            doas /run/current-system/sw/bin/nixos-rebuild switch --flake $HOME/.config/nix $_nr_args 2>&1 | tee -a $_nr_log
            set _nr_switch_ok $pipestatus[1]
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
    # (B) Refresh the baseline after a successful --update (the lock and the
    # overlay pins changed); also create it after the first successful run.
    # Deliberately NOT refreshed on plain successful nr: the lock did not
    # change, so the measured value would be identical.
    if test "$_nr_switch_ok" -eq 0
        if test "$_nr_update" = yes; or not test -s $_nr_base_file
            echo "nr: refreshing local-build baseline (about a minute)…"
            __nr_local_builds "$_nr_ref" >$_nr_base_file.tmp
            if test $status -eq 0
                command mv $_nr_base_file.tmp $_nr_base_file
                echo "nr: baseline: "(count (command cat $_nr_base_file))" local builds"
            else
                command rm -f $_nr_base_file.tmp
                echo "nr: WARNING: baseline refresh failed — keeping the old baseline" >&2
            end
        end
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
