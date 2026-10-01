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
        # License must be set consciously by every caller. Defaulting to
        # `mit` silently mislabelled every overlay that forgot, so the default
        # is `unfree` — a loud, obviously-wrong value that fails
        # allowUnfree=false evaluations rather than quietly claiming MIT.
        license = lib.licenses.unfree;
      }
      // meta;
  })
