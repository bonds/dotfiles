{
  lib,
  stdenv,
  autoPatchelfHook,
  patchelfUnstable,
  adwaita-icon-theme,
  dbus-glib,
  libXtst,
  curl,
  gtk3,
  alsa-lib,
  libva,
  pciutils,
  pipewire,
  fetchurl,
  version,
  url,
  hash,
}:
# Linux half of the unified zen-browser overlay: builds upstream's prebuilt
# tarball. ./default.nix wraps the result with nixpkgs' firefox wrapper (as
# youwen5/zen-browser-flake did), which is where the shared zen-policies.nix is
# applied via extraPolicies.
stdenv.mkDerivation {
  pname = "zen-browser-unwrapped";
  inherit version;
  applicationName = "Zen Browser";

  src = fetchurl {
    inherit url hash;
  };

  nativeBuildInputs = [
    autoPatchelfHook
    patchelfUnstable
  ];

  buildInputs = [
    gtk3
    alsa-lib
    adwaita-icon-theme
    dbus-glib
    libXtst
  ];

  runtimeDependencies = [
    curl
    libva.out
    pciutils
  ];

  appendRunpaths = [
    "${pipewire}/lib"
  ];

  installPhase = ''
    mkdir -p "$prefix/lib/zen-${version}"
    cp -r * "$prefix/lib/zen-${version}"

    mkdir -p $out/bin
    ln -s "$prefix/lib/zen-${version}/zen" $out/bin/zen
  '';

  # See the nixpkgs firefox wrapper: keeping old .note.gnu.property sections
  # makes the prebuilt binaries fail to load.
  patchelfFlags = ["--no-clobber-old-sections"];

  passthru = {
    inherit gtk3;
    libName = "zen-${version}";
    binaryName = "zen";
    gssSupport = true;
    ffmpegSupport = true;
  };

  meta = {
    mainProgram = "zen";
    description = "Zen is a privacy-focused browser that blocks trackers, ads, and other unwanted content while offering the best browsing experience";
    homepage = "https://zen-browser.app";
    license = lib.licenses.mpl20;
    platforms = ["x86_64-linux"];
  };
}
