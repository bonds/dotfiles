# Self-expiring override for OpenCode, pinned to the **V2** line.
#
# Why this file exists: nixpkgs ships the V1 line (1.19.0 on nixpkgs-unstable)
# and V2 is a ground-up rewrite. V2 is published on npm as `@opencode/cli`; the
# actual binary lives in the per-platform payload package
# `@opencode/cli-darwin-arm64`. Up to v2.2.4 the V2 tags carried no GitHub
# release assets at all, so `releases/latest` still pointed at V1 and the 1.x
# `releases/download/v<ver>/opencode-darwin-arm64.zip` URL shape was gone. The
# CLI therefore still comes from the npm tarball (sha512-checked against npm's
# own metadata); the desktop app, which npm never published, comes from the
# release zip that exists again from v2.2.5 on.
#
# Self-expiry: comparing `pkgs.opencode.version` to a version on a *different
# product line* is meaningless (1.19.x is the V1 line, not an older V2), so we
# only warn if nixpkgs ever ships >= 2.0.0. We never substitute `prev.opencode`
# on that signal: a silent swap would change packaging shape underneath us, and
# the V1-named package is not the same artifact as this one.
#
# ROLLBACK: V1 and V2 both install the `opencode` binary and read the same
# config locations, so they cannot coexist. To go back to V1 1.19.4:
#   git -C $HOME/.local/share/dotfiles/worktree revert <this-bump-sha>
#   nr
# (The V1 pin — CLI sha256-xACi+MirfplHin9N0aRmtXvzOIjlINhcVXgKVGTEtok= — stays
# in git history; do not delete it from history as the escape hatch.)
nixpkgs: final: prev: let
  cliVersion = "2.2.6";
  cliHash = "sha256-YT67dN2O/3Z7udRCo3tAxNmUa6J/FTiYUGihuWeBN6M=";

  # No npm package exists for the desktop app, so it comes from the release zip.
  # V2 only started shipping Electron assets at v2.2.5 (298 MB zip, 756 MB
  # unpacked). update.sh bumps this pin from the same tag and cross-checks the
  # download against the release's SHA256SUMS; if a tag ships no desktop asset
  # it leaves the pin alone with a warning rather than aiming the URL at a 404.
  desktopVersion = "2.2.6";
  desktopHash = "sha256-hOt1Kf5bZcjIaoWq1uYQa9wphTTOrRh9cfk+BAu5CyE=";

  basePkgs = import nixpkgs {
    system = "aarch64-darwin";
    config.allowUnfree = true;
  };
  nixpkgsHasV2 = prev.lib.versionAtLeast basePkgs.opencode.version "2.0.0";
in
  prev.lib.warnIf nixpkgsHasV2
  "opencode >= 2.0.0 is now in nixpkgs, the V2 half of this overlay can be removed."
  {
    opencode = final.mkDarwinPackage {
      pname = "opencode";
      version = cliVersion;

      # npm tarball for the darwin/arm64 payload. 214 MB unpacked; the tarball
      # contains package/bin/opencode and package/package.json only.
      src = prev.fetchurl {
        url = "https://registry.npmjs.org/@opencode/cli-darwin-arm64/-/cli-darwin-arm64-${cliVersion}.tgz";
        hash = cliHash;
      };

      # stdenvNoCC would hand the .tgz to unpackPhase; extract the one member we
      # want explicitly instead so the layout is unambiguous.
      dontUnpack = true;

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        tar -xzf "$src" package/bin/opencode
        install -m 755 package/bin/opencode $out/bin/opencode
        runHook postInstall
      '';

      meta = {
        description = "AI coding agent built for the terminal (V2 line)";
        homepage = "https://opencode.ai";
        license = prev.lib.licenses.mit;
        platforms = ["aarch64-darwin"];
      };
    };

    opencode-desktop = final.mkDarwinPackage rec {
      pname = "opencode-desktop";
      version = desktopVersion;

      src = prev.fetchurl {
        url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-desktop-mac-arm64.zip";
        hash = desktopHash;
      };

      nativeBuildInputs = [prev.unzip];

      installPhase = ''
        mkdir -p $out/Applications $out/bin
        cp -r OpenCode.app $out/Applications/
        rm -f $out/Applications/OpenCode.app/Contents/Resources/app-update.yml
        ln -s $out/Applications/OpenCode.app/Contents/MacOS/OpenCode $out/bin/opencode-desktop

        # Re-sign ad-hoc. Removing app-update.yml above rewrites a bundle
        # that still carries the vendor's Developer ID signature, which
        # breaks the code-signature seal — macOS then reports the app as
        # "damaged". --deep covers the nested frameworks/helpers.
        /usr/bin/codesign --force --deep --sign - $out/Applications/OpenCode.app
      '';

      meta = {
        description = "OpenCode Desktop App (auto-updater disabled)";
        homepage = "https://github.com/anomalyco/opencode";
        license = prev.lib.licenses.mit;
        platforms = ["aarch64-darwin"];
      };
    };
  }
