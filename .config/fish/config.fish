# Commands to run in interactive sessions can go here

# add all the paths I like
set --append fish_user_paths ~/bin/(string lower (uname))
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

if status --is-interactive
#    devbox global shellenv --init-hook | source
    if command --query starship
        if locale 2>&1 | grep -q UTF-8
            set -x STARSHIP_CONFIG ~/.config/starship/unicode.toml
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
if test (uname) = Darwin
    set -x SSH_AUTH_SOCK /Users/scott/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh
end

# install the fisher plugin manager (and plugins) if its not installed yet
if not functions --query fisher
    # don't start an infinite recursion when we start a new fish instance to
    # install fisher
    if test "$installing_fisher" != "TRUE"
        set -x installing_fisher TRUE
        curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
        # restore my plugins list after its overwritten by the installer
        git restore ~/.config/fish/fish_plugins
        # and then install all my plugins
        fisher update
    end
end

# aliases for convenience
alias ssh "ssh -F ~/.config/ssh/config"
alias crawl "crawl -rc ~/.config/crawl/init.txt"
alias day "date '+%Y%m%d'"
alias ghci "ghci -ghci-script ~/.config/ghc/ghci.rio.conf -ghci-script ~/.config/ghc/ghci.conf"
alias height "tput lines"
alias idris "rlwrap --history-filename ~/.local/idris.history idris2 --package contrib"
alias myip "curl --silent https://checkip.amazonaws.com"
# alias python "python3.10"
alias width "tput cols"
alias chatgpt "set -x OPENAI_API_KEY (security find-generic-password -w -a $LOGNAME -s \"openai api key\"); and command chatgpt"

# OS specific aliases
if test (uname) = Darwin
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

function ls
    if command --query lsd
        lsd $argv
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
       ping $argv
    end 
end

set fzf_directory_opts --bind "ctrl-o:execute($EDITOR {} &> /dev/tty)"
set fzf_fd_opts --hidden --exclude=.git
