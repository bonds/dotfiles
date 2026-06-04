# Commands to run in interactive sessions can go here

set uname (string lower (uname))

if command --query ionice
    alias nice "command nice ionice -c idle"
end

# add all the paths I like
set --append fish_user_paths ~/bin/"$uname"
set --append fish_user_paths ~/bin
set --append fish_user_paths ~/.local/bin
set --append fish_user_paths ~/.cargo/bin
# for building idris2 on openbsd
# remember to run pkg_add racket-minimal
# remember to run raco pkg install compiler-lib

# set where I want Idris2 looking for packages
set -x IDRIS2_PREFIX ~/.local/lib

# nix flakes needs this
set -x NIXPKGS_ALLOW_UNFREE 1

# my favorite date format
set -x DATEFMT "+%F %T"

set -x PASSAGE_DIR $HOME/.config/passage/store
set -x PASSAGE_IDENTITIES_FILE $HOME/.config/passage/identities

if status --is-interactive
    if command --query starship
        set ssc "$HOME/.config/starship/$uname.toml"
        if locale 2>&1 | grep -q UTF-8; and test -e "$ssc"
            set -x STARSHIP_CONFIG $ssc
        else
            set -x STARSHIP_CONFIG ~/.config/starship/plain.toml
        end
        starship init fish | source # cool prompt
    end
    if command --query atuin
        atuin init fish | source # shell history database
    end
end

if status --is-interactive && test -n "$SSH_CONNECTION" && not set --query TMUX && command --query tmux
    exec tmux -u -T RGB new -A -s remote \; set -g default-terminal "tmux-256color" \; set -sg escape-time 0
end

# use the hardware SSH key in my TPM
if test "$uname" = darwin
    set -x SSH_AUTH_SOCK /Users/scott/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh
end

# aliases for convenience
alias chatgpt "set -x OPENAI_API_KEY (security find-generic-password -w -a $LOGNAME -s \"openai api key\"); and command chatgpt"
alias crawl "crawl -rc ~/.config/crawl/init.txt"
alias day "date '+%Y%m%d'"
alias ghci "ghci -ghci-script ~/.config/ghc/ghci.rio.conf -ghci-script ~/.config/ghc/ghci.conf"
alias height "tput lines"
alias idris "rlwrap --history-filename ~/.local/idris.history idris2 --package contrib"
alias myip "mylocation | jq \".ip\" | sed 's/\\\"//g'"
alias myweather "weather (mylocation | jq \".loc\" | sed 's/\\\"//g')"
alias nix-shell "command nix-shell --command fish"
alias reset_camera "sudo usb-reset 0fd9:008a"
alias reset_usb "sudo rmmod xhci_pci; sudo modprobe xhci_pci"
alias reset_mouse "sudo rmmod hid_magicmouse; sudo modprobe hid_magicmouse"
alias sshc "ssh -o RequestTTY=no -o RemoteCommand=none"
alias ssh-clean "rm ~/.local/ssh/*.control"
alias ssht "ssh -o RemoteCommand=none"
alias width "tput cols"
alias xclip "command xclip -selection c"

# OS specific aliases
if test "$uname" = darwin
    alias mtr "sudo mtr"
    alias battery "pmset -g batt"
end

# choose the best editor available
if command --query hx
    set -x EDITOR hx
else if command --query helix
    set -x EDITOR helix
else if command --query kak
    set -x EDITOR kak
else if command --query nvim
    set -x EDITOR nvim
else if command --query vim
    set -x EDITOR vim
else
    set -x EDITOR vi
end

alias ssh "command ssh -F ~/.config/ssh/config"

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
            echo $(date "+%Y-%m-%d %H:%M"): $pong
        end
    end
end

function nr
    if contains -- --update $argv
        and test "$uname" = darwin
        update-ollama --no-rebuild
    end
    if test "$uname" = darwin
        nh darwin switch $HOME/.config/nix $argv
    else
        nh os switch $HOME/.config/nix $argv
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

set fzf_directory_opts --bind "ctrl-o:execute($EDITOR {} &> /dev/tty)"
set fzf_fd_opts --hidden --exclude=.git

# Added by LM Studio CLI (lms)
set -gx PATH $PATH /Users/scott/.lmstudio/bin
# End of LM Studio CLI section
