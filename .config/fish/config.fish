# Commands to run in interactive sessions can go here

# if test -n "$SSH_CONNECTION"
#     set from (echo $SSH_CONNECTION | awk '{print $1}')
#     set to (echo $SSH_CONNECTION | awk '{print $3}')
#     gnome-session-inhibit \
#         --app-id scott@ggr.com \
#         --reason "is SSHed into $hostname ($to) from $from" \
#         --inhibit-only &
# end

set uname (string lower (uname))

if command --query ionice
    alias nice "command nice ionice -c idle"
end

# add all the paths I like
set --append fish_user_paths ~/bin/"$uname"
set --append fish_user_paths ~/bin
set --append fish_user_paths ~/.local/bin
set --append fish_user_paths ~/.cargo/bin
# set --append fish_user_paths ~/Library/Python/3.10/bin

# for python
source $VENV_DIR/bin/activate.fish

# workaround for a bug in ghc 9.0.2: https://gitlab.haskell.org/ghc/ghc/-/issues/20592
if command --query xcrun
    set -x C_INCLUDE_PATH (xcrun --show-sdk-path)/usr/include/ffi
end

# set where I want Idris2 looking for packages
set -x IDRIS2_PREFIX ~/.local/lib

# nix flakes needs this
set -x NIXPKGS_ALLOW_UNFREE 1

# devbox on linux needs this
set -x NIX_REMOTE daemon

# docker cli on util.local needs this
set -x DOCKER_HOST ssh://root@172.16.0.100

# my favorite date format
set -x DATEFMT "+%F %T"

set -x PASSAGE_DIR $HOME/.config/passage/store
set -x PASSAGE_IDENTITIES_FILE $HOME/.config/passage/identities

if not set --query NIX_CONFIG
    set -x NIX_CONFIG (rage -d -i ~/.config/passage/(hostname).identity ~/.config/passage/store/NIX_CONFIG.age)
end

if status --is-interactive
    #    devbox global shellenv --init-hook | source
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

# use the hardware SSH key in my TPM
if test "$uname" = darwin
    set -x SSH_AUTH_SOCK /Users/scott/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh
end

# install the fisher plugin manager (and plugins) if its not installed yet
if not functions --query fisher
    # don't start an infinite recursion when we start a new fish instance to
    # install fisher
    if test "$installing_fisher" != TRUE
        set -x installing_fisher TRUE
        curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
        # restore my plugins list after its overwritten by the installer
        git restore ~/.config/fish/fish_plugins
        # and then install all my plugins
        fisher update
    end
end

# aliases for convenience
alias chatgpt "set -x OPENAI_API_KEY (security find-generic-password -w -a $LOGNAME -s \"openai api key\"); and command chatgpt"
alias crawl "crawl -rc ~/.config/crawl/init.txt"
alias day "date '+%Y%m%d'"
alias ghci "ghci -ghci-script ~/.config/ghc/ghci.rio.conf -ghci-script ~/.config/ghc/ghci.conf"
alias height "tput lines"
alias idris "rlwrap --history-filename ~/.local/idris.history idris2 --package contrib"
# alias myip "curl --silent https://checkip.amazonaws.com"
alias myip "mylocation | jq \".ip\" | sed 's/\\\"//g'"
alias myweather "weather (mylocation | jq \".loc\" | sed 's/\\\"//g')"
alias nix "command nix --extra-experimental-features nix-command --extra-experimental-features flakes"
alias nix-shell "command nix-shell --command fish"
alias reset_camera "sudo usb-reset 0fd9:008a"
alias reset_usb "sudo rmmod xhci_pci; sudo modprobe xhci_pci"
alias sshc "ssh -o RequestTTY=no -o RemoteCommand=none"
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

function ssh
    if test $uname = darwin
        set timeoutflag G
    else
        set timeoutflag w
    end
    if test $argv[1] = metanoia;
        and not nc -z -$timeoutflag 1 metanoia 22 >/dev/null 2>&1
        echo -n trying to wake metanoia before SSHing in
        wol "a8:a1:59:36:7d:d4"
        while not nc -z -$timeoutflag 1 metanoia 22 >/dev/null 2>&1
            echo -n .
            sleep 1
        end
    end
    command ssh -F ~/.config/ssh/config $argv
end

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

if command --query nh_darwin
    alias nh "nice nh_darwin"
else
    alias nh "nice command nh"
end

# https://nixos-and-flakes.thiscute.world/nixos-with-flakes/update-the-system
function nr
    set starting_dir (pwd)
    set config_dir $HOME/.config/nix
    cd $config_dir
    nice -- nix flake update
    nh os switch . $argv
    if command --query ulauncher
        systemctl --user restart ulauncher
    end
    cd $starting_dir
end

function hr
    nice home-manager $argv switch --flake ~/.config/nix
end

function nix
    # set -x NIX_CONFIG (secret-tool lookup name 'NIX_CONFIG')
    # set -x NIX_CONFIG (passage NIX_CONFIG)
    command nix --extra-experimental-features nix-command --extra-experimental-features flakes $argv
end

set fzf_directory_opts --bind "ctrl-o:execute($EDITOR {} &> /dev/tty)"
set fzf_fd_opts --hidden --exclude=.git
