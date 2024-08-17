# if INIT=$(devbox global shellenv --init-hook); then
#   echo Starting DevBox...
#   eval "$INIT"
# elif which fish 2>&1 >/dev/null; then
if which fish 2>&1 >/dev/null; then
  exec fish
fi
