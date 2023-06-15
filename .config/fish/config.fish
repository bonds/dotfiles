# Commands to run in interactive sessions can go here

# installed by ghcup
set -q GHCUP_INSTALL_BASE_PREFIX[1]; or set GHCUP_INSTALL_BASE_PREFIX $HOME ; set -gx PATH $HOME/.cabal/bin $PATH /Users/scott/.ghcup/bin # ghcup-env

# workaround for a bug in ghc 9.0.2: https://gitlab.haskell.org/ghc/ghc/-/issues/20592
set -x C_INCLUDE_PATH (xcrun --show-sdk-path)/usr/include/ffi

# nix flakes needs this
set -x NIXPKGS_ALLOW_UNFREE 1

if status --is-interactive
    # devbox global shellenv --init-hook | source
    atuin init fish | source
end

# use the hardware SSH key in my TPM
set -x SSH_AUTH_SOCK /Users/scott/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh

# install the fisher plugin manager (and plugins) if its not installed yet
if not functions --query fisher
    curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher
    fisher update
end

# add paths to my PATH
set fish_user_paths ~/bin ~/.local/bin