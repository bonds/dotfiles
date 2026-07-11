---
slug: photos-direct-rsync
status: awaiting-approval
intent: clear
review_required: false
pending-action: write .omo/plans/photos-direct-rsync.md
approach: "Keep osxphotos export with --export-as-hardlink flag (near-zero local disk), replace Syncthing with nightly rsync to sophrosyne over LAN."
---

# Draft: photos-direct-rsync

## Components (topology ledger)
<!-- id | outcome (one line) | status: active|deferred | evidence path -->

| id | outcome | status | evidence |
|----|---------|--------|----------|
| ssh-key | Secretive public key in `~/.config/ssh/keys` updated by user | done | User: "BTW I fixed the ssh key for sophrosyne" |
| photos-export-agent | osxphotos launchd agent at `hosts/accismus/configuration.nix:208-229` runs `osxphotos export --skip-edited --skip-live --update --directory "{created.year}/{created.month:02d}" ~/Pictures/Syncthing-Photos/` | active | `hosts/accismus/configuration.nix:208-229` |
| syncthing-photos | Sendonly folder in `syncthing-config.xml:6-9` syncing `~/Pictures/Syncthing-Photos/` to sophrosyne | active | `hosts/accismus/syncthing-config.xml:6-9` |
| server-photos-dir | sophrosyne receives photos at `/dragon/media/photos` via Syncthing (receiveonly), firesafe backs it up | active | `hosts/sophrosyne/configuration.nix:277-282,322` |
| export-structure | Current export at `~/Pictures/Syncthing-Photos/` has date-organized dirs: `2026/04/`, etc. | confirmed | `read: /Users/scott/Pictures/Syncthing-Photos` |
| disk-constraint | Cannot keep 2 copies of 1TB+ on accismus SSD | stated by user | Problem statement |
| hardlink-capability | osxphotos --export-as-hardlink creates hardlinks on APFS (zero extra disk) | confirmed | Context7 docs: osxphotos CLI has `--export-as-hardlink` option for creating hardlinks instead of copies |

## Open assumptions (announced defaults)
<!-- assumption | adopted default | rationale | reversible? -->

| assumption | adopted default | rationale | reversible? |
|-----------|----------------|----------|-------------|
| Date-organized structure not needed | UUID-named files from originals/ rsync are sufficient | User explicitly chose "Not important" for date organization | Yes (change approach later) |
| Files in `originals/` are readable by user-level processes | rsync from launchd agent as `scott` can read them | Originals are regular files owned by user, not locked by Photos (database is locked, not media files) | N/A - if wrong, fall back to osxphotos export |
| LAN access at night | rsync over `192.168.4.43` (local IP, per SSH Match block) | User confirmed "Same LAN at night" | Yes |
| "Download Originals to this Mac" is set | All originals are local | User confirmed this setting | N/A - required precondition |
| Don't propagate deletions | No `--delete` flag on rsync — files stay on server forever | Backup semantics (matches current Syncthing sendonly behavior) | Yes |

## Findings (cited - path:lines)

1. **SSH key mismatch**: Secretive agent offers key with fingerprint `SHA256:U487fmdSmRFWtvyTcNYogg6iHbN2pmCJ0sdufKuuelo` (comment: `scott's-super-secure-thing@secretive.Scott's-MacBook-Air.local`). Authorized key in `~/.config/ssh/keys` has fingerprint `SHA256:R6/SeIB9qL5ugYfchgdxIrXhe862ve55Q8VJnz6fH04` (comment: `scott@ggr.com.macbookair.touchid`). Different keys. Source: `hosts/sophrosyne/configuration.nix:81-84` (activation script copies `.config/ssh/keys` to `/etc/ssh/authorized_keys.d/scott`).

2. **Current osxphotos export** runs nightly at 2am via launchd user agent: `ProgramArguments = ["/Applications/Nix Apps/OSXPhotos.app/Contents/MacOS/osxphotos", "export", "--skip-edited", "--skip-live", "--update", "--directory", "{created.year}/{created.month:02d}", "/Users/scott/Pictures/Syncthing-Photos"]`. Source: `hosts/accismus/configuration.nix:208-229`.

3. **Syncthing Photos folder** is `sendonly` on accismus (path `~/Pictures/Syncthing-Photos/`, folder id `photos`), `receiveonly` on sophrosyne (path `/dragon/media/photos/`). Source: `hosts/accismus/syncthing-config.xml:6-9` and `hosts/sophrosyne/configuration.nix:277-282`.

4. **Firesafe backup** sources `/dragon/media/photos` on sophrosyne. Source: `hosts/sophrosyne/configuration.nix:322`.

5. **Sophrosyne LAN IP**: `192.168.4.43` per SSH Match block at `~/.config/ssh/config:19-20`. Remote via `home.ggr.com`.

6. **Sophrosyne has mDNS disabled** (`services.avahi.enable = false`), so `sophrosyne.local` doesn't resolve. Source: `hosts/sophrosyne/configuration.nix:143`.

7. **rsync 3.4.4** is available on accismus at `/run/current-system/sw/bin/rsync`. Source: bg_a9907a85.

8. **osxphotos has `--export-as-hardlink` CLI option** which creates hardlinks (zero extra disk on APFS). Source: osxphotos CLI docs via Context7.

## Decisions (with rationale)

1. **Keep osxphotos export with `--export-as-hardlink`** — Creates date-organized directory structure at near-zero extra disk cost (hardlinks on APFS share data blocks with originals). User wants date organization. Context7 confirmed the CLI option exists.
2. **Replace Syncthing with rsync for photos** — Single nightly batch transfer instead of continuous sync. Avoids hardlink safety risk (Syncthing modifying timestamps on hardlinks would propagate to originals since they share an inode). rsync is read-only on source.
3. **No `--delete` on rsync** — Backup semantics: files stay on server even if deleted locally. Matches current Syncthing sendonly behavior.
4. **Keep osxphotos `--update` flag** — Enables incremental export. `.osxphotos_export.db` tracks changes so subsequent runs only process new/changed files.
5. **Keep `--skip-edited --skip-live`** — Same selection as current pipeline. Only original unedited photos and only the still image (not Live Photo video) are exported.
6. **Add `--sidecar-xmp`** — Writes XMP metadata sidecars alongside each photo (keywords, GPS, dates, descriptions). User chose this for browsable metadata on the server without backing up the locked SQLite database.
7. **Target same path on server: `/dragon/media/photos`** — Firesafe config needs zero changes. Existing date-organized files from old pipeline remain as a historical snapshot alongside new ones.
8. **Run both steps in one launchd agent at 2am** — Single agent runs export then rsync sequentially. Same schedule as current.
9. **SSH key already fixed by user** — Prerequisite met.

## Scope IN

- Add `--export-as-hardlink` and `--sidecar-xmp` flags to osxphotos export command in launchd agent
- Add rsync step in the same launchd agent (after export completes) to transfer export to sophrosyne
- Rename agent from `photos-export` to `photos-backup`
- Clear existing `~/Pictures/Syncthing-Photos/` and `.osxphotos_export.db` so first hardlink export is clean
- Remove Photos folder from accismus Syncthing config
- Remove Photos folder from sophrosyne Syncthing config
- Rebuild sophrosyne (SSH key update + syncthing config removal)
- Run initial export (fast — hardlinks only) then initial rsync seed (3-6h over LAN)
- Update AGENTS.md photos pipeline documentation
- Keep `/dragon/media/photos` as the destination — firesafe backup continues unchanged

## Scope OUT (Must NOT have)

- Do NOT modify the firesafe backup module or its config
- Do NOT modify how the Photos app works or its storage settings
- Do NOT touch the osxphotos package or overlay — leave it installed (may be useful for other tasks)
- Do NOT modify SSH config or network setup
- Do NOT attempt to migrate/merge the existing date-organized photos on sophrosyne — let them sit as archive
- Do NOT add `--delete` to the rsync command
- Do NOT touch other Syncthing folders (Documents remains)

## Open questions

None — all forks resolved via exploration or user answers.

## Approval gate
status: awaiting-approval
<!-- When exploration is exhausted and unknowns are answered, set status: awaiting-approval. -->
<!-- That durable record is the loop guard: on a later turn read it and resume at the gate instead of re-running exploration. -->
