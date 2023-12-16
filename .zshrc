INIT=$(devbox global shellenv --init-hook 2>&1 >/dev/null)

if [[ $? -eq 0 ]]; then
  echo Starting DevBox...
  eval $INIT
else
  exec fish
fi

