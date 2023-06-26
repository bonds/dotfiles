# Commands to run in interactive sessions can go here

# add all the paths I like
set --append fish_user_paths ~/bin/(string lower (uname))
set --append fish_user_paths ~/bin
set --append fish_user_paths ~/.local/bin
set --append fish_user_paths ~/.cargo/bin

# workaround for a bug in ghc 9.0.2: https://gitlab.haskell.org/ghc/ghc/-/issues/20592
if command --query xcrun
    set -x C_INCLUDE_PATH (xcrun --show-sdk-path)/usr/include/ffi
end

# nix flakes needs this
set -x NIXPKGS_ALLOW_UNFREE 1

if status --is-interactive
#    devbox global shellenv --init-hook | source
    if command --query starship
        starship init fish | source # cool prompt
    end
    if command --query atuin
        atuin init fish | source # shell history database
    end
end

# use the hardware SSH key in my TPM
set -x SSH_AUTH_SOCK /Users/scott/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh

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
alias angband "angband -mgcu -- -n4"
alias crawl "crawl -rc ~/.config/crawl/init.txt"
alias day "date '+%Y%m%d'"
alias ghci "ghci -ghci-script ~/.config/ghc/ghci.conf"
alias height "tput lines"
alias idris "rlwrap idris2"
alias myip "curl --silent https://checkip.amazonaws.com"
alias python "python3.10"
alias width "tput cols"

# OS specific aliases
if test (uname) = Darwin; alias mtr "sudo mtr"; end

# choose the best editor available
if command --query hx
    set -x EDITOR hx
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
        ls $argv
    end
end

function e --description "shortcut to the default editor"
    if command --query fzf; and test -z "$argv"
        $EDITOR (fzf)
    else
        $EDITOR $argv
    end
end
