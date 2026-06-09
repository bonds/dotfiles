set -g _os (string lower (uname))

if test "$_os" = linux; and command --query ionice
    alias nice "command nice ionice -c idle"
end

set --append fish_user_paths ~/bin/"$_os"
set --append fish_user_paths ~/bin
set --append fish_user_paths ~/.local/bin
set --append fish_user_paths ~/.cargo/bin

set -x IDRIS2_PREFIX ~/.local/lib
set -x NIXPKGS_ALLOW_UNFREE 1
set -x DATEFMT "+%F %T"
set -x PASSAGE_DIR $HOME/.config/passage/store
set -x PASSAGE_IDENTITIES_FILE $HOME/.config/passage/identities
