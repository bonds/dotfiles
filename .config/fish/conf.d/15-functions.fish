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
            update-ollama --no-rebuild
            update-zen-browser --no-rebuild
            update-opencode --no-rebuild
        else
            update-huggingface-hub --no-rebuild
        end
    end
    if test "$_os" = darwin
        nh darwin switch $HOME/.config/nix $argv
    else
        nh os switch $HOME/.config/nix $argv
    end
    if test "$_os" = darwin
        set _nr_new_system (command readlink -f /nix/var/nix/profiles/system 2>/dev/null)
    else
        set _nr_new_system (command readlink -f /run/current-system 2>/dev/null)
    end
    if test "$_nr_old_system" != "$_nr_new_system"
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
