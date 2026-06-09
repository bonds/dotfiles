function ls
    if command --query lsd
        lsd --hyperlink=auto $argv
    else if command --query colorls
        colorls -G $argv
    else
        command ls $argv
    end
end

function e --description "shortcut to the default editor"
    if command --query fzf; and test -z "$argv"
        $EDITOR (fzf)
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

function ping
    if command --query ts
        command ping $argv | ts '%Y-%m-%d %H:%M'
    else
        command ping $argv | while read pong
            echo (date "+%Y-%m-%d %H:%M"): $pong
        end
    end
end

function nr
    set -l _nr_old_system (command readlink /run/current-system)
    if contains -- --update $argv
        and test "$uname" = darwin
        update-ollama --no-rebuild
    end
    if test "$uname" = darwin
        nh darwin switch $HOME/.config/nix $argv
    else
        nh os switch $HOME/.config/nix $argv
    end
    set -l _nr_new_system (command readlink /run/current-system)
    if test "$_nr_old_system" != "$_nr_new_system"
        what-changed "$_nr_old_system" "$_nr_new_system"
    end
end

function hr
    nice home-manager $argv switch --flake ~/.config/nix
end

function age
    if command --query rage
        rage $argv
    else
        command age $argv
    end
end
