{
  stdenvNoCC,
  lib,
}: {
  pname,
  version,
  src,
  installPhase,
  nativeBuildInputs ? [],
  sourceRoot ? ".",
  dontFixup ? true,
  dontStrip ? true,
  meta ? {},
  ...
} @ attrs:
stdenvNoCC.mkDerivation (attrs
  // {
    inherit sourceRoot dontFixup dontStrip;
    meta =
      {
        platforms = ["aarch64-darwin"];
        mainProgram = pname;
        license = lib.licenses.mit;
      }
      // meta;
  })
