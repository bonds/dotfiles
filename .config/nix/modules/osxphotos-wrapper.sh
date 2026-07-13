#!/bin/sh
real_bin="@out@/lib/osxphotos"
library="$HOME/Pictures/Photos Library.photoslibrary"

case "${1:-}" in
  list)
    echo "$library"
    ;;
  help|about|version|docs|shell-completion|tutorial|theme|install|uninstall|update)
    exec "$real_bin" "$@"
    ;;
  -*|'')
    # options (--version, -h) or bare invocation — no library injection
    exec "$real_bin" "$@"
    ;;
  *)
    for arg in "$@"; do
      case "$arg" in --library|--db) has_lib=1; break;; esac
    done
    if [ -n "${has_lib-}" ]; then
      exec "$real_bin" "$@"
    else
      exec "$real_bin" "$1" --library "$library" "${@:2}"
    fi
    ;;
esac
