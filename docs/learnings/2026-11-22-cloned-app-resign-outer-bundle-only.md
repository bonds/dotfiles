# Cloning a macOS .app for a second Dock identity: re-sign the outer bundle only

**Date:** 2026-11-22

## Symptom

A cloned `Ghostty.app` renamed to `Pi.app` — new `CFBundleIdentifier`, main executable replaced by a wrapper script, then `codesign --force --deep --sign -` — verified with `codesign --verify --deep --strict` and still refused to launch: "PiTest is damaged and can't be opened. You should move it to the Trash."

## Cause

`--deep` re-signs every nested bundle ad-hoc, which throws away the Developer ID identity and the hardened-runtime entitlements of the original (`codesign -dvv` showed `flags=0x10000(runtime)`, `Authority=Developer ID Application: …`, plus `com.apple.security.automation.apple-events` / `device.audio-input` / …). macOS reports *any* failed signature validation as "damaged" rather than "unsigned", so the message points at the file, not the signature.

## Fix / takeaway

Modify only what is not code, and sign only the outer bundle: `codesign --force --sign - Pi.app` (no `--deep`). Nested frameworks keep their signatures, the main executable keeps its identity and entitlements, and the new outer seal covers the edited Info.plist. To make the clone behave differently without touching the binary, redirect its config: Ghostty honours `XDG_CONFIG_HOME` on macOS (`XDG_CONFIG_HOME=/tmp/x ghostty +show-config` reports values from `/tmp/x/ghostty/config`) and its Info.plist already has an `LSEnvironment` dict, so `Set :LSEnvironment:XDG_CONFIG_HOME <dir>` gives the clone its own config where `command`, `macos-icon` and `macos-custom-icon` differ. Also `chmod -R u+w` the copy: `/Applications/Ghostty.app` here is read-only, so `cp -R` propagates that and every later edit fails with "Permission denied".
