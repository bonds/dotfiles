# Shared checks for the modules/overlays/*/verify.sh smoke tests.
#
# Sourced, not executed: each hook is `<dir>/verify.sh <system-path> <pname>
# <package-out-path>`, called by `nr-pins verify` after a successful build and
# before `nr` switches to it. Exit 0 = healthy, non-zero = this package is
# broken; `nr-pins` then reverts the directory to its last committed pin.
#
# What these checks are worth: they catch a package that will not start, reports
# the wrong version, or whose code-signature seal was broken by our own
# post-processing (stripping app-update.yml, re-signing ad-hoc) — all of which
# `nix build` happily accepts and the user only discovers on first launch. They
# cannot prove an app actually works once running.
#
# shellcheck shell=bash

verify_app() { # verify_app <app-bundle> <expected-version>
    local app="$1" want="$2" got
    [ -d "$app" ] || {
        echo "verify: $app is missing from the built package" >&2
        return 1
    }
    # The seal check is the point: the overlay rewrites the bundle (removing
    # app-update.yml, re-signing ad-hoc) and a botched rewrite makes macOS call
    # the app "damaged" on launch, which no build-time check notices.
    if ! codesign --verify --deep --strict "$app" > /dev/null 2>&1; then
        echo "verify: $app fails 'codesign --verify --deep --strict' — the signature seal is broken" >&2
        codesign --verify --deep --strict "$app" 2>&1 | head -3 >&2
        return 1
    fi
    got="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
        "$app/Contents/Info.plist" 2> /dev/null || true)"
    [ -n "$got" ] || {
        echo "verify: $app has no CFBundleShortVersionString in its Info.plist" >&2
        return 1
    }
    # The bundle must be the version the derivation claims: a prebuilt asset that
    # does not match its pin (wrong platform, stale CDN copy) builds fine.
    [ "$got" = "$want" ] || {
        echo "verify: $app reports version '$got', the derivation says '$want'" >&2
        return 1
    }
    return 0
}

verify_no_updater() { # verify_no_updater <app-bundle> — app-update.yml must be gone
    local app="$1"
    if [ -e "$app/Contents/Resources/app-update.yml" ]; then
        echo "verify: $app/Contents/Resources/app-update.yml is back — the Electron auto-updater was not stripped" >&2
        return 1
    fi
    return 0
}
