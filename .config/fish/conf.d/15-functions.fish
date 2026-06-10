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
        command ping $argv | ts '%Y-%m-%d %H:%M'
    else
        command ping $argv | while read pong
            echo (date "+%Y-%m-%d %H:%M"): $pong
        end
    end
end

function nr
    if test "$_os" = darwin
        set -l _nr_old_system (command readlink /nix/var/nix/profiles/system 2>/dev/null)
    else
        set -l _nr_old_system (command readlink /run/current-system 2>/dev/null)
    end
    if contains -- --update $argv
        and test "$_os" = darwin
        update-ollama --no-rebuild
    end
    if test "$_os" = darwin
        nh darwin switch $HOME/.config/nix $argv
    else
        nh os switch $HOME/.config/nix $argv
    end
    if test "$_os" = darwin
        set -l _nr_new_system (command readlink /nix/var/nix/profiles/system 2>/dev/null)
    else
        set -l _nr_new_system (command readlink /run/current-system 2>/dev/null)
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
