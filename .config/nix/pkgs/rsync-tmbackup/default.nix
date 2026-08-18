{
  lib,
  stdenv,
  fetchurl,
}:
stdenv.mkDerivation rec {
  pname = "rsync-tmbackup";
  version = "0-unstable-2025-05-27";

  src = fetchurl {
    url = "https://raw.githubusercontent.com/laurent22/rsync-time-backup/9b3ea2d41036bcebb8da4564cab35b5019a552cd/rsync_tmbackup.sh";
    hash = "sha256-965nZ0Siw88M21U2P2K46Q+q3aJ75oSPzdPZTrYUonU=";
  };

  phases = ["installPhase"];

  installPhase = ''
    mkdir -p $out/bin
    sed '1c\
    #!${stdenv.shell}' "$src" > "$out/bin/rsync-tmbackup"
    chmod +x "$out/bin/rsync-tmbackup"
  '';

  meta = {
    description = "Time Machine-style backup with rsync (hard-linked incremental snapshots)";
    homepage = "https://github.com/laurent22/rsync-time-backup";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = [];
  };
}
