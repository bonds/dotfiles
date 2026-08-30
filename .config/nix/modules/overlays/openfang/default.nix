# OpenFang desktop app — Tauri 2.0 native wrapper for the OpenFang Agent OS,
# with the kernel + API server embedded in the single binary.
#
# Distributed as a prebuilt `OpenFang_aarch64.app.tar.gz` from GitHub releases
# (not in nixpkgs — project is pre-1.0 and shipping fast, so we pin to a release
# and bump via `nr --update` + update.sh, matching the other binary overlays).
_nixpkgs: final: prev: {
  openfang-desktop = final.mkDarwinPackage rec {
    pname = "openfang-desktop";
    version = "0.6.9";

    src = prev.fetchurl {
      url = "https://github.com/RightNow-AI/openfang/releases/download/v${version}/OpenFang_aarch64.app.tar.gz";
      hash = "sha256-VymkbpwUCcjZt0G5pIpsMoiDrY98U3Xn4wZHvSSpBH8=";
    };

    # Use the host /usr/bin/tar (bsdtar) for extraction — avoids pulling GNU tar
    # as a nativeBuildInput, which nix would compile from source (slow), and is
    # the same host-tool pattern the other darwin overlays use for sips/iconutil.
    installPhase = ''
      mkdir -p $out/Applications
      /usr/bin/tar xzf "$src" -C "$out/Applications"
      APP="$out/Applications/OpenFang.app"

      # The bundled _CodeSignature was made on the original build machine; in
      # the read-only nix store it is invalid for the new location, and an
      # unsigned store-bundled app is rejected by Gatekeeper. Strip it and
      # re-sign ad-hoc so LaunchServices/Spotlight accept the app.
      chmod -R u+w "$APP"
      rm -rf "$APP/Contents/_CodeSignature"
      /usr/bin/codesign --force -s - "$APP"
    '';

    meta = {
      description = "OpenFang desktop app (agent OS, Tauri with embedded kernel)";
      homepage = "https://github.com/RightNow-AI/openfang";
      license = prev.lib.licenses.asl20;
    };
  };
}
