# LM Studio CLI (`lms`).
#
# It lives in a conf.d file, not in config.fish, because `lms` appends its own
# block to ~/.config/fish/config.fish and ~/.zshrc when it cannot find the
# directory on PATH. Both of those are tracked, so an append leaves $HOME dirty
# and `nr` refuses to apply main — which is what happened on 2026-11-20 after an
# LM Studio update. Providing the path here keeps the tool out of tracked files.
#
# `set --append fish_user_paths` rather than `fish_add_path`: the latter persists
# itself by writing a `set -g fish_user_paths …` line into config.fish, which is
# the very thing this file exists to prevent.
if test "$_os" = darwin
    set --append fish_user_paths ~/.lmstudio/bin
end
