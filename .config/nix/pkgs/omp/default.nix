{
  lib,
  stdenv,
  fetchurl,
}:
# OMP (`oh-my-pi`, omp.sh) — the coding agent that can1357 forked from pi.
#
# Deliberately the PREBUILT release binary, not upstream's nix package. Their
# `packages.<system>.omp` builds the agent from source (bun bundle + ~80k lines
# of Rust natives through crane, fat LTO) and no substituter carries it, so
# every bump would cost a long local build on every `nr --update` — exactly the
# trade-off flake.nix refuses for pi ("a from-source build with no binary
# cache"). The release asset is a single self-contained bun executable, and
# upstream's own install script does the same thing after verifying its
# SHA-256; here the hash is pinned in git instead.
#
# `dontStrip`/`dontFixup` are load-bearing: stripping a signed Mach-O on Apple
# Silicon invalidates its code signature and the kernel then kills it on exec
# ("Killed: 9"), and there is no source here to strip anything useful out of.
#
# `nr --update` bumps this file via update.sh (a prebuilt pkgs/ directory: see
# the overlay-pin section of nr-pins). The hash lines below are the ones
# update.sh rewrites and the ones nr-pins reverts a bad bump from, so keep each
# hash on its own `name = "sha256-…";` line.
stdenv.mkDerivation rec {
  pname = "omp";
  version = "19.0.1";

  # Release asset for the platform being built. Only the two systems this flake
  # declares are carried; update.sh refreshes both hashes from the release's
  # SHA256SUMS.txt, so a bump made on accismus stays correct for sophrosyne.
  asset =
    if stdenv.hostPlatform.system == "aarch64-darwin"
    then "omp-darwin-arm64"
    else if stdenv.hostPlatform.system == "x86_64-linux"
    then "omp-linux-x64"
    else throw "omp: no prebuilt release asset for ${stdenv.hostPlatform.system}";

  hash = "sha256-L+Qgu9APgYmYFuUcvuuVk6+lnZNo1iydPnhTXVQOMvY=";
  linuxHash = "sha256-bO7wRDCFG7EFDG/aOvRnQS60ShHfCm/4Eh/mAQE8VBU=";

  src = fetchurl {
    url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/${asset}";
    hash =
      if stdenv.hostPlatform.system == "aarch64-darwin"
      then hash
      else linuxHash;
  };

  dontUnpack = true;
  dontStrip = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/omp
    runHook postInstall
  '';

  meta = with lib; {
    description = "OMP coding agent with the IDE wired in (pi fork by Stencil Labs)";
    homepage = "https://omp.sh";
    license = licenses.mit;
    mainProgram = "omp";
    platforms = ["aarch64-darwin" "x86_64-linux"];
  };
}
