{
  lib,
  stdenv,
  fetchurl,
  unzip,
}:
stdenv.mkDerivation rec {
  pname = "ghosttile";
  version = "2.0.9";

  src = fetchurl {
    url = "https://github.com/hewigovens/ghosttile-cli/releases/download/v${version}/GhostTile-${version}.zip";
    hash = "sha256-4GmrfWNse66LsCRqBQvUARHHOxrZJcY6ezXPFDbJaJQ=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [unzip];

  installPhase = ''
    mkdir -p $out/Applications
    cp -r GhostTile.app $out/Applications/
  '';

  dontFixup = true;

  meta = with lib; {
    description = "Hide apps from Dock and Cmd+Tab";
    homepage = "https://github.com/hewigovens/ghosttile-cli";
    platforms = platforms.darwin;
  };
}
