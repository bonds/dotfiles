{
  stdenvNoCC,
  lib,
}: {
  pname,
  sourceRoot ? ".",
  dontFixup ? true,
  dontStrip ? true,
  platforms ? ["aarch64-darwin"],
  meta ? {},
  ...
} @ attrs:
stdenvNoCC.mkDerivation (attrs
  // {
    inherit sourceRoot dontFixup dontStrip;
    meta =
      {
        inherit platforms;
        mainProgram = pname;
        license = lib.licenses.mit;
      }
      // meta;
  })
