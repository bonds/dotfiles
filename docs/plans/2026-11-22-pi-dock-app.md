# A `Pi.app` with its own Dock icon

**Status:** proposed · last moved 2026-11-22 · nothing built in the repo. A
throwaway clone was built in `/tmp`, verified end to end, and deleted — the
commands below are the ones that worked.

## Why

Every pi session shares Ghostty's Dock icon and ⌘-Tab entry with every plain
shell, so "switch to my agent" and "switch to a terminal" look identical. The
Dock icon belongs to the `.app` that owns the window, so the only way to give pi
its own is a second app bundle — a clone of Ghostty.app that runs `pi`.

## Verified on this machine (do not re-derive)

- **The Dock icon cannot be delegated.** A wrapper app (Platypus, `appify`,
  Automator, an `LSUIElement` launcher) leaves the window owned by Ghostty, so
  the icon stays Ghostty's; a non-terminal wrapper gives no TTY. iTerm2 profiles,
  Alacritty and kitty have no per-window or per-profile icon either. Cloning the
  terminal bundle is the only route that works.
- **Ghostty honours `XDG_CONFIG_HOME` on macOS**, so a clone can have its own
  config with the binary untouched:
  `XDG_CONFIG_HOME=/tmp/x ghostty +show-config | grep font-size` reports the value
  from `/tmp/x/ghostty/config`. (A first test with an *invalid* key looked like a
  false negative — unknown keys in a config file do not set a non-zero exit code.)
- **Ghostty's `Info.plist` already has an `LSEnvironment` dict** holding
  `GHOSTTY_MAC_LAUNCH_SOURCE = app`, so add a key to it; do not replace the dict.
- **`/Applications/Ghostty.app` is read-only** (`dr-xr-xr-x`, files `-r--r--r--`,
  version 1.3.1, 62 MB), so `cp -R` makes a read-only copy and every later edit
  fails with "Permission denied". `chmod -R u+w` the copy — or use `cp -Rc`
  (APFS clonefile), which is instant and costs no extra disk.
- **Sign the outer bundle only**: `codesign --force --sign - Pi.app`. Adding
  `--deep` re-signs Sparkle and the main binary ad-hoc, strips Ghostty's
  Developer ID identity and hardened-runtime entitlements, and macOS then refuses
  to launch with "… is damaged and can't be opened" — the full diagnosis is in
  `docs/learnings/2026-11-22-cloned-app-resign-outer-bundle-only.md`.
- Verified working clone: `codesign --verify --deep --strict` passed,
  `open -a` launched it, `lsappinfo` reported `bundleID="com.scott.pi"`, and it
  read its own config directory (its own `command` wrote a proof file).

## Decisions

**D1 — Clone the terminal bundle.** Rejected: a wrapper app, because the icon
follows window ownership, and every non-terminal wrapper loses the TTY. Rejected:
per-profile icons in iTerm2, which do not exist.

**D2 — Redirect config with `LSEnvironment` + `XDG_CONFIG_HOME`, never by
replacing the executable.** Rejected: a `Contents/MacOS/ghostty` shell script that
`exec`s the real binary, which is what produced the "damaged" dialog: changing the
main executable forces re-signing code, and `--deep` throws away the Developer ID
signature and entitlements.

**D3 — Build it in an activation script, not a derivation.** Ghostty here is
hand-installed and read-only, not a nix package, so a derivation would have to
copy from `/Applications` at build time (impure) or pin a second Ghostty from
nixpkgs (62 MB, version skew with the one actually used). Rejected: a one-off
manual copy, which goes stale silently the next time Ghostty updates. The
activation script is idempotent and self-healing: rebuild when Ghostty's
`CFBundleShortVersionString` changes **or** when the clone's
`CFBundleIdentifier` is no longer `com.scott.pi` (Sparkle may have replaced it —
see D6).

**D4 — Icon: generated π `.icns`.** Matches the existing
`modules/overlays/*/<name>-icon.icns` precedent (`hermes`, `osaurus`, `zen`).
Rejected: a built-in Ghostty style (`holographic`, `xray`, …), which is zero work
but not pi's mark. Note the Dock icon comes from `macos-icon = custom` +
`macos-custom-icon`; the *Finder* icon needs `CFBundleIconName` deleted and
`CFBundleIconFile` set, because the asset catalog wins over an `.icns`.

**D5 — The clone inherits the main config, then overrides.** Its config is
`config-file = ~/.config/ghostty/config` first, so font, theme and keybinds stay
in step, then `command`, `wait-after-command = true`, `macos-icon`,
`macos-custom-icon`. Rejected: duplicating the config, which silently diverges.

**D6 — Assume Sparkle can replace the clone.** Ghostty has no `SUFeedURL` in its
plist (it is set in code), so the clone cannot be trusted to stay a clone. Do not
try to defeat it: make D3's self-healing check the bundle id, so a replaced clone
is rebuilt on the next `nr`.

## Phases

**P1 — the clone exists and launches.**
`modules/home/pi-dock-app.nix`: `home.activation` script that clones
`/Applications/Ghostty.app` to `~/Applications/Pi.app`, patches
`CFBundleIdentifier` / `CFBundleName` / `CFBundleDisplayName` /
`LSEnvironment:XDG_CONFIG_HOME`, signs the outer bundle, and stamps Ghostty's
version next to it. Test: `lsappinfo list | rg com.scott.pi` after launching it
from Finder, and a second `nr` changes nothing (stamp unchanged, no re-copy).

**P2 — it runs pi.** `~/.config/pi-ghostty/ghostty/config` per D5, committed as a
tracked file. Test: launching `Pi.app` opens a window running `pi`; launching
Ghostty still opens a plain shell (the two configs do not leak).

**P3 — the icon.** Generate a π `.icns` (`sips` + `iconutil`), add
`macos-custom-icon`, and optionally patch `CFBundleIconFile` for Finder. Test:
Dock shows the π mark while Ghostty keeps its own; relaunching after `nr` keeps
it.

**P4 — polish, only if it earns its keep.** Quiet Sparkle's update UI in the
clone's plist, and decide whether `wait-after-command` should stay (a window that
survives `pi` exiting) or close like any other app.

## Open questions

- Does a Finder-launched clone see the same `PATH` a shell does? `command` must
  be an absolute path (`/run/current-system/sw/bin/pi`) for that reason — confirm
  nothing else in the config assumes the login shell's environment.
- TCC prompts (camera, microphone, Apple events) are granted per bundle id, so
  the clone starts with none. Harmless for pi; note it if a future pi feature
  needs them.
- `home.activation` ordering: the script must run after the home files it
  references are linked, and must not fail the switch if `/Applications/Ghostty.app`
  is missing (say, on a fresh machine) — it should warn and continue.
