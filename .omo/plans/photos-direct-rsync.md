# photos-direct-rsync - Work Plan

## TL;DR (For humans)

**What you'll get:** A nightly backup of every photo from your Mac's Photos app to the sophrosyne server, organized by date (`2026/04/IMG_1234.HEIC`), with **zero extra space used on your laptop**. The key trick: osxphotos creates hardlinks instead of copies — APFS shares the data blocks with the originals inside the Photos library. Then rsync sends those files to sophrosyne over your home LAN. No more Syncthing for photos. No more 1TB duplicate on your SSD.

**Why this approach:** Hardlinks on APFS mean the exported directory structure costs only a few KB per file in directory entries — the actual data lives once in the Photos library. rsync over LAN replaces the slower continuous Syncthing sync with a single daily batch. You keep the date-organized folders you want.

**What it will NOT do:** It won't delete photos from the server when you delete them from Photos (backup semantics — no `--delete` on rsync). It won't touch other Syncthing folders (Documents stays). It won't change the firesafe setup. It won't modify the Photos app or its library.

**Effort:** Medium (3-4 files to edit, 1 server rebuild, ~30m initial export + ~3-6h initial rsync seed)
**Risk:** Low — migration is additive. Old Syncthing pipeline is removed only after new pipeline verifies.
**Decisions to sanity-check:** (1) Clearing `Syncthing-Photos/` for a clean hardlink-export start — the files are still on sophrosyne via Syncthing. (2) Removing Syncthing Photos folder after verifying rsync works. (3) No `--delete` — files accumulate forever on the server.

Your next move: **Approve** this plan and I'll write the changes.

---

> TL;DR (machine): Medium effort, low risk. Add `--export-as-hardlink` and `--sidecar-xmp` to osxphotos export, add rsync step to same launchd agent, remove Syncthing Photos folder from both sides, clear old full-copy export, fresh seed via hardlink-export→rsync, update docs.

## Scope
### Must have
- Add `--export-as-hardlink` and `--sidecar-xmp` to the osxphotos export command in the launchd agent
- Add rsync of the export directory to `sophrosyne:/dragon/media/photos/` as a second step in the same launchd agent
- Rename agent from `photos-export` to `photos-backup` (clean break)
- Clear old full-copy export: delete `~/Pictures/Syncthing-Photos/*` and `.osxphotos_export.db`
- Remove Photos folder from accismus Syncthing config (`syncthing-config.xml`)
- Remove Photos folder from sophrosyne Syncthing config (`hosts/sophrosyne/configuration.nix`)
- Rebuild sophrosyne (deploys SSH key fix + syncthing config change)
- Run initial `--export-as-hardlink` export (~30m for 1TB, hardlinks are fast) then initial rsync seed (~3-6h)
- Update AGENTS.md to document the new pipeline

### Must NOT have (guardrails, anti-slop, scope boundaries)
- Do NOT modify the firesafe backup module or its sources (it already sources `/dragon/media/photos`)
- Do NOT modify how the Photos app works, its storage settings, or its library structure
- Do NOT remove osxphotos from the nix config (it's the core of this pipeline)
- Do NOT touch SSH config, network config, or firewall
- Do NOT add `--delete` to the rsync command (backup semantics)
- Do NOT modify other Syncthing folders (Documents stays)
- Do NOT clear Syncthing-Photos until the new launchd agent is built and ready to run
- Do NOT delete the old export until AFTER the initial rsync seed completes on sophrosyne

## Verification strategy
> Zero human intervention — all verification is agent-executed.
- Test decision: tests-after — verify each step with concrete assertions
- Evidence: `.omo/evidence/task-<N>-photos-direct-rsync.<ext>`

## Execution strategy
### Parallel execution waves

**Wave 0 (Pre-clean):** Clear old full-copy export, delete `.osxphotos_export.db`
**Wave 1 (Accismus config):** Update launchd agent with `--export-as-hardlink` + `--sidecar-xmp` + rsync step, remove Syncthing Photos folder
**Wave 2 (Server config):** Remove Syncthing Photos folder from sophrosyne config, rebuild sophrosyne
**Wave 3 (Seed):** Run initial hardlink export, then initial rsync (3-6h)
**Wave 4 (Cleanup):** Update AGENTS.md, final verification

### Dependency matrix
| Todo | Depends on | Blocks | Can parallelize with |
| --- | --- | --- | --- |
| 1. Update launchd agent (add `--export-as-hardlink`, add rsync step, rename) | — | 2, 3, 4 | — |
| 2. Update accismus Syncthing config (remove Photos folder) | — | 3, 4 | 1 |
| 3. Update sophrosyne config (remove Photos folder) + rebuild | 1, 2 | 4 | — |
| 4. Initial seed (clear old export → hardlink export → rsync) | 1, 2, 3 | 5 | — |
| 5. Update AGENTS.md | 4 | F1-F4 | — |

## Todos
> Implementation + Test = ONE todo. Never separate.
<!-- APPEND TASK BATCHES BELOW THIS LINE WITH edit/apply_patch - never rewrite the headers above. -->

- [ ] 1. **Update launchd agent: add `--export-as-hardlink` and rsync step, rename to `photos-backup`**
  *What to do / Must NOT do:* In `hosts/accismus/configuration.nix`:
  
  1. Replace the `photos-export` launchd agent (lines 208-229) with a new `photos-backup` agent.
  
  2. The agent should run a shell script (not a direct command) since it has two steps. Use `ProgramArguments` with `/bin/sh -c` and the full pipeline:
  ```bash
  osxphotos export --export-as-hardlink --sidecar-xmp --skip-edited --skip-live --update --directory "{created.year}/{created.month:02d}" /Users/scott/Pictures/Syncthing-Photos/ && rsync -a --stats /Users/scott/Pictures/Syncthing-Photos/ sophrosyne:/dragon/media/photos/
  ```
  
  3. Schedule: same `StartCalendarInterval` (Hour=2, Minute=0).
  
  4. StandardOutPath: `/tmp/photos-backup.out.log`, StandardErrorPath: `/tmp/photos-backup.err.log`.
  
  *Command construction:*
  ```nix
  "photos-backup" = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          ${pkgs.osxphotos}/bin/osxphotos export --export-as-hardlink --sidecar-xmp --skip-edited --skip-live --update --directory "{created.year}/{created.month:02d}" /Users/scott/Pictures/Syncthing-Photos/ \
          && rsync -a --stats /Users/scott/Pictures/Syncthing-Photos/ sophrosyne:/dragon/media/photos/
        ''
      ];
      StartCalendarInterval = [
        {
          Hour = 2;
          Minute = 0;
        }
      ];
      StandardOutPath = "/tmp/photos-backup.out.log";
      StandardErrorPath = "/tmp/photos-backup.err.log";
    };
  };
  ```
  
  Must NOT do: Do NOT add `--delete` to rsync. Do NOT change the export destination path (must stay `~/Pictures/Syncthing-Photos/`). Do NOT remove osxphotos from systemPackages.
  
  *Parallelization:* Wave 1 | Blocked by: — | Blocks: 3, 4
  
  *References:* `hosts/accismus/configuration.nix:208-229` (current photos-export agent), osxphotos docs confirming `--export-as-hardlink` flag
  
  *Acceptance criteria:* After `nr` rebuild: `launchctl list | grep photos-backup` shows loaded. `launchctl list | grep photos-export` returns nothing. The launchd plist at `~/Library/LaunchAgents/` has the new name.
  
  *QA scenarios:* Check the plist file content: `plutil -p ~/Library/LaunchAgents/org.nixos.photos-backup.plist` should show the export + rsync command. Evidence `.omo/evidence/task-1-photos-direct-rsync.txt`
  
  *Commit:* Y | `feat(photos): add --export-as-hardlink and rsync step in photos-backup agent`

- [ ] 2. **Remove Photos folder from accismus Syncthing config**
  *What to do / Must NOT do:* In `hosts/accismus/syncthing-config.xml`:
  
  1. Remove the `<folder id="photos" ...>` XML block (lines 6-9):
  ```xml
  <folder id="photos" label="Photos" path="/Users/scott/Pictures/Syncthing-Photos" type="sendonly" rescanIntervalS="3600" fsWatcherEnabled="true" fsWatcherDelayS="10">
      <filesystemType>basic</filesystemType>
      <device id="252R7DN-6HAEVP2-PXIAG6D-6JU2NCP-QEGULBE-I532CRV-4C6XA46-DKEUBAO"></device>
  </folder>
  ```
  
  2. Keep the Documents folder and all other configuration unchanged.
  
  Must NOT do: Do NOT remove other folders (Documents). Do NOT remove device entries.
  
  *Parallelization:* Wave 1 | Blocked by: — | Blocks: 3, 4 (can run in parallel with Todo 1)
  
  *References:* `hosts/accismus/syncthing-config.xml:6-9`
  
  *Acceptance criteria:* After `nr` rebuild: Syncthing should no longer show a Photos folder in its web UI (localhost:8384). grep for 'folder id="photos"' in syncthing-config.xml returns nothing.
  
  *QA scenarios:* `grep 'folder id="photos"' hosts/accismus/syncthing-config.xml` should return no matches. Evidence `.omo/evidence/task-2-photos-direct-rsync.txt`
  
  *Commit:* (part of Todo 1 commit since both are in the same nix config push)

- [ ] 3. **Remove Photos folder from sophrosyne Syncthing config + rebuild**
  *What to do / Must NOT do:* In `hosts/sophrosyne/configuration.nix`:
  
  1. Remove the `Photos` entry from `services.syncthing.settings.folders` (lines 277-282):
  ```nix
  "Photos" = {
    path = "/dragon/media/photos";
    id = "photos";
    type = "receiveonly";
    devices = ["accismus"];
  };
  ```
  
  2. Keep the `Documents` folder entry unchanged.
  
  3. After committing and pushing: `config push origin && config push sophrosyne`
  
  4. SSH to sophrosyne and rebuild: `ssh sophrosyne "doas /run/current-system/sw/bin/nixos-rebuild switch --flake /home/scott/.config/nix#sophrosyne"`
  
  Must NOT do: Do NOT remove the firesafe `Photos` source entry (line 322). Do NOT remove other syncthing folders. Do NOT change anything else in the sophrosyne config.
  
  *Parallelization:* Wave 2 | Blocked by: 1, 2 | Blocks: 4
  
  *References:* `hosts/sophrosyne/configuration.nix:277-282` (Syncthing Photos folder)
  
  *Acceptance criteria:* After rebuild: `ssh sophrosyne "cat /home/scott/.config/syncthing/config.xml | grep photos"` returns nothing. `ssh sophrosyne "ls /dragon/media/photos/"` still shows the existing date-organized folders (they persist, just Syncthing stops managing them).
  
  *QA scenarios:* SSH in and check the syncthing config. Then also check `doas systemctl status syncthing.service` for any errors. Evidence `.omo/evidence/task-3-photos-direct-rsync.txt`
  
  *Commit:* (part of Todo 1 commit)

- [ ] 4. **Seed initial transfer: clear old export, run hardlink export, rsync to sophrosyne**
  *What to do / Must NOT do:* 
  
  1. **BEFORE starting:** Confirm todos 1-3 are done and rebuilt. The new `photos-backup` agent is loaded but we'll run manually for the initial seed.
  
  2. **Clear old full-copy export** — Delete the existing files in `Syncthing-Photos/` to start fresh with hardlinks:
  ```bash
  rm -rf /Users/scott/Pictures/Syncthing-Photos/*
  rm -f /Users/scott/Pictures/Syncthing-Photos/.osxphotos_export.db
  rm -f /Users/scott/Pictures/Syncthing-Photos/.osxphotos_export.db-shm
  rm -f /Users/scott/Pictures/Syncthing-Photos/.osxphotos_export.db-wal
  ```
  
  Note: The `.stfolder/` directory should remain (Syncthing uses it for folder identification) — though Syncthing no longer manages this folder, it's harmless. Do NOT delete `.stfolder/` or `.stversions/`.
  
  3. **Run osxphotos export with hardlinks** — This creates the date-organized directory structure as hardlinks. Should be fast (~30m for 1TB since no data is copied):
  ```bash
  /run/current-system/sw/bin/osxphotos export --export-as-hardlink --sidecar-xmp --skip-edited --skip-live --update --directory "{created.year}/{created.month:02d}" /Users/scott/Pictures/Syncthing-Photos/
  ```
  
  4. **Verify export was created as hardlinks** — Check that files are hardlinks (link count > 1):
  ```bash
  ls -la /Users/scott/Pictures/Syncthing-Photos/2026/04/ | head -5
  ```
  The link count column (second field) should be 2+ for hardlinked files (one link in originals/, one in Syncthing-Photos/).
  
  5. **Run initial rsync seed** — This transfers all data to sophrosyne. Run it manually (not via launchd) since it takes 3-6 hours:
  ```bash
  rsync -aHAX --info=progress2 --stats /Users/scott/Pictures/Syncthing-Photos/ sophrosyne:/dragon/media/photos/
  ```
  
  6. **Verify the seed** — After completion, run a dry-run to confirm zero files pending:
  ```bash
  rsync -aHAX --dry-run --stats /Users/scott/Pictures/Syncthing-Photos/ sophrosyne:/dragon/media/photos/
  ```
  The stats should show "Number of files transferred: 0" (or close to zero).
  
  Must NOT do: Do NOT run the rsync over WAN (too slow for 1TB). Do NOT interrupt the export or rsync. Do NOT delete old export files until step 3 completes (the hardlink export needs to succeed first). Do NOT add `--delete` to rsync.
  
  *Parallelization:* Wave 3 | Blocked by: 3 | Blocks: 5
  
  *References:* Todo 1 (rsync command in launchd agent), `~/.ssh/config` for sophrosyne host resolution
  
  *Acceptance criteria:* `rsync --dry-run --stats` shows 0 files to transfer. `ssh sophrosyne "du -sh /dragon/media/photos/"` shows ~1TB. Date-organized directories exist on sophrosyne: `ssh sophrosyne "ls /dragon/media/photos/2026/"` shows month directories.
  
  *QA scenarios:* Compare total size: `du -sh /Users/scott/Pictures/Syncthing-Photos/` vs `ssh sophrosyne "du -sh /dragon/media/photos/"` should be similar. Compare file count too. Check a few specific recent files exist on both sides. Verify XMP sidecars are present: `ssh sophrosyne "find /dragon/media/photos/2026 -name '*.xmp' | head -5"` should return XMP files. Evidence `.omo/evidence/task-4-photos-direct-rsync.txt`
  
  *Commit:* N/A (execution only)

- [ ] 5. **Update AGENTS.md photos pipeline documentation**
  *What to do / Must NOT do:* In `/Users/scott/AGENTS.md`, update the Photos pipeline section (under accismus machine bullet):
  
  Replace the current block (about photos export via osxphotos launchd agent + Syncthing sync) with:
  
  ```
  - **Photos backup** via `photos-backup` launchd agent (daily at 2am). Two-step pipeline:
    1. `osxphotos export --export-as-hardlink` — reads originals from Photos library, creates date-organized hardlinks in `~/Pictures/Syncthing-Photos/` (near-zero extra disk on APFS)
    2. `rsync` — transfers the export directory to `sophrosyne:/dragon/media/photos/` over SSH LAN
    - **⚠️ Prerequisite:** In Photos → Settings → General, set "Download Originals to this Mac" (not "Optimize Mac Storage"). If set to Optimize, the export silently gets low-resolution thumbnails and the backup copies are useless. Easy to miss on a fresh account since Photos defaults to Optimize.
    - **No `--delete`:** rsync does NOT use --delete, so files removed from Photos remain on the server (backup semantics).
    - **Hardlinks:** The export uses `--export-as-hardlink`, so the organized directory costs only directory-entry metadata — no data duplication.
    - **Metadata sidecars:** `--sidecar-xmp` writes an XMP sidecar file next to each photo (keywords, GPS, dates, titles), giving browsable metadata on the server.
  ```
  
  Also remove any reference to Syncthing syncing photos (the photos pipeline no longer involves Syncthing).
  
  Keep the Syncthing section for Documents — that still uses it.
  
  Must NOT do: Do NOT remove the "Download Originals to this Mac" prerequisite warning — it's still critical. Do NOT remove osxphotos from the package list in AGENTS.md.
  
  *Parallelization:* Wave 4 | Blocked by: 4 | Blocks: F1-F4
  
  *References:* `/Users/scott/AGENTS.md` (current text mentions osxphotos export + Syncthing sync)
  
  *Acceptance criteria:* AGENTS.md no longer references Syncthing for photos. The new two-step pipeline with hardlinks is documented.
  
  *QA scenarios:* `grep "Syncthing.*[Pp]hoto\|photos-export\|Photos export" AGENTS.md` should return no matches. `grep "export-as-hardlink\|photos-backup" AGENTS.md` should find the new documentation. Evidence `.omo/evidence/task-5-photos-direct-rsync.txt`
  
  *Commit:* Y | `docs(photos): update AGENTS.md for --export-as-hardlink + rsync pipeline`

## Final verification wave
> Runs in parallel after ALL todos. ALL must APPROVE. Surface results and wait for the user's explicit okay before declaring complete.
- [ ] F1. **Plan compliance audit** — Verify all scope items completed, nothing in Must NOT have violated.
- [ ] F2. **Real ssh test** — `ssh sophrosyne "echo Connected; df -h /dragon; ls /dragon/media/photos/2026/ | head -10"` confirms server reachable and date-organized photos exist.
- [ ] F3. **rsync dry-run** — `rsync -aHAX --dry-run --stats /Users/scott/Pictures/Syncthing-Photos/ sophrosyne:/dragon/media/photos/` shows zero files pending.
- [ ] F4. **Firesafe config check** — `ssh sophrosyne "grep -n Photos /home/scott/.config/nix/hosts/sophrosyne/configuration.nix"` confirms firesafe still sources `/dragon/media/photos`.
- [ ] F5. **No Syncthing Photos folder** — `grep 'folder id="photos"' hosts/accismus/syncthing-config.xml` returns nothing. `ssh sophrosyne "grep photos /home/scott/.config/syncthing/config.xml"` returns nothing.

## Commit strategy

Two commits (squash-merge into main):

1. `feat(photos): add --export-as-hardlink, replace Syncthing with rsync`
   - Files: `hosts/accismus/configuration.nix`, `hosts/accismus/syncthing-config.xml`, `hosts/sophrosyne/configuration.nix`

2. `docs(photos): update AGENTS.md for --export-as-hardlink + rsync pipeline`
   - File: `AGENTS.md`

Push after commit 1: `config push origin && config push sophrosyne`
Then rebuild sophrosyne: `ssh sophrosyne "doas /run/current-system/sw/bin/nixos-rebuild switch --flake /home/scott/.config/nix#sophrosyne"`
Then run initial seed (Todo 4).
Then commit 2.

## Success criteria

- [ ] `launchctl list | grep photos-backup` shows loaded service on accismus
- [ ] `launchctl list | grep photos-export` returns nothing (old agent gone)
- [ ] No Photos folder in accismus or sophrosyne Syncthing config
- [ ] `~/Pictures/Syncthing-Photos/` contains date-organized hardlinks (link count 2+) with `.xmp` sidecars alongside photos
- [ ] `/dragon/media/photos/` on sophrosyne has all photos in date-organized folders
- [ ] `rsync --dry-run` shows zero files pending
- [ ] Firesafe backup still sources `/dragon/media/photos` unchanged
- [ ] AGENTS.md documents the new pipeline
- [ ] Nightly run at 2am: export (hardlinks) → rsync (incremental)
