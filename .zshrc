if INIT=$(devbox global shellenv --init-hook); then
  echo Starting DevBox...
  eval "$INIT"
else
  exec fish
fi
