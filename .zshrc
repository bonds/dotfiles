# if INIT=$(devbox global shellenv --init-hook); then
#   echo Starting DevBox...
#   eval "$INIT"
# elif which fish 2>&1 >/dev/null; then

# Nix
if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
  . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi
# End Nix

if which fish 2>&1 >/dev/null; then
  exec fish
fi


