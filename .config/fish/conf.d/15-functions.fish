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
    set -l _nr_old_system
    set -l _nr_new_system
    if test "$_os" = darwin
        set _nr_old_system (command readlink -f /nix/var/nix/profiles/system 2>/dev/null)
    else
        set _nr_old_system (command readlink -f /run/current-system 2>/dev/null)
    end
    if contains -- --update $argv
        if test "$_os" = darwin
            set -l _pwd $PWD
            cd $HOME/.config/nix
            bash pkgs/oxillama/update.sh
            bash modules/overlays/zen-browser/update.sh
            bash modules/overlays/opencode/update.sh
            bash modules/overlays/daisydisk-overlay/update.sh
            bash modules/overlays/osaurus/update.sh
            alejandra pkgs/oxillama/default.nix modules/overlays/zen-browser/default.nix modules/overlays/opencode/default.nix modules/overlays/daisydisk-overlay/default.nix modules/overlays/osaurus/default.nix
            cd $_pwd
        else
            set -l _pwd $PWD
            cd $HOME/.config/nix
            bash pkgs/bedrock-server/update.sh
            alejandra pkgs/bedrock-server/default.nix
            cd $_pwd
        end
    end
    if test "$_os" = darwin
        nh darwin switch $HOME/.config/nix $argv
    else
        nh os switch $HOME/.config/nix $argv -e auto
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

function backup-status --description "Check restic backup status"
    set -l repo "sftp:restic-backup@192.168.4.43:/dragon/backups/accismus"
    set -l pwfile "$HOME/.config/restic/password"

    if not test -f "$pwfile"
        echo "No password file at $pwfile — has restic init been run?" >&2
        return 1
    end

    if not ping -c 1 -t 1 192.168.4.43 >/dev/null 2>&1
        echo "Not on home network (192.168.4.x unreachable)" >&2
        return 1
    end

    set -lx RESTIC_PASSWORD_FILE "$pwfile"

    switch "$argv[1]"
        case snapshots s
            restic -r "$repo" -o "sftp.args=-i $HOME/.ssh/id_restic_backup -o ControlMaster=no" snapshots
        case logs l
            tail -20 ~/Library/Logs/restic-backup.out.log
        case server
            ssh sophrosyne "doas restic -r /dragon/backups/accismus snapshots --password-file /run/agenix/restic-password"
        case last
            restic -r "$repo" -o "sftp.args=-i $HOME/.ssh/id_restic_backup -o ControlMaster=no" snapshots --latest 1
        case '*'
            echo "Usage: backup-status [snapshots|logs|server|last]"
            echo "  snapshots (s) — list recent backups"
            echo "  logs (l)     — last 20 lines of backup log"
            echo "  server       — check snapshots from server side"
            echo "  last         — show most recent snapshot"
    end
end

function nix-shell
    if contains -- --command $argv; or contains -- --run $argv
        command nix-shell $argv
    else
        command nix-shell --command fish $argv
    end
end
