# Plan: Promote `/dragon/media` to a ZFS dataset

> **Status:** Archived — deferred 2026-07-05. The 8.7T of I/O on a degraded pool
> wasn't worth the cosmetic benefit. Photos were moved to `/dragon/media/photos`
> (via mountpoint change) without touching the rest of media; see
> `hosts/sophrosyne/configuration.nix:278,322` for the path references that were
> updated.

## What we wanted

Make `dragon/media` a proper ZFS dataset (independent snapshots, quotas,
atime=off) containing all current media *and* photos as subdirectories. Then
re-parent `dragon/photos` under it (as a subdirectory, not its own dataset).

## What we found (survey, Jul 2026)

### Pool state
- **Pool:** `dragon`, 29.1T total, 22.1T allocated, 7.02T free, 20% frag
- **State:** `DEGRADED` (intentional — raidz2 with 1 device offline, 1-of-2
  redundancy)
- **ZFS datasets:**
  ```
  dragon          /dragon          (atime=on, 16.5T used)
  dragon/photos   /dragon/photos   (atime=off, 164G, 0 snapshots)
  dragon/servers  /dragon/servers  (atime=off, 48G, 0 snapshots)
  ```
- **No snapshots** on any dataset → destructive ops (rm, zfs destroy) reclaim
  space immediately, but also zero rollback capability.

### `/dragon/media` current state
- **Not a dataset** — plain directory on the `dragon` root dataset.
- **8.7T total** across 8 subdirectories:

  | subdir       | size   |
  |--------------|--------|
  | movies       | 4.7T   |
  | tvshows      | 3.6T   |
  | music        | 217G   |
  | software     | 177G   |
  | iphone       | 56G    |
  | audiobooks   | 54G    |
  | books        | 8.9G   |
  | manuals      | 990M   |

- **Ownership:** `nobody:nogroup 0555` (read-only), subdirs also `nobody:nogroup`
  — set for Samba guest share.
- **Samba:** served read-only at `\\sophrosyne\media\` (guest ok, writeable=no).
- **Firesafe sources:** backs up each subdir individually (e.g.
  `"Media/movies" = "/dragon/media/movies"`).

### `/dragon/photos` references in nix (the 2 that were changed)
1. `hosts/sophrosyne/configuration.nix:278` — syncthing `Photos` folder `path`
2. `hosts/sophrosyne/configuration.nix:322` — firesafe `Photos` source

### Syncthing
- `photos` folder is receive-only on sophrosyne; send-only on accismus (Mac).
- Runs as `scott:users`. Folder id `photos`. No `.stignore`.
- Mac-side config needs **no changes** for a path move — folder id stays the same.

## The deferred approach (incremental rsync)

Would require copying 8.7T from the `dragon` dataset into a new `dragon/media`
dataset, then destroying the source files on `dragon`.

### Phase 1: Create staging dataset

```bash
doas zfs create dragon/medianew
doas zfs set atime=off dragon/medianew
chown nobody:nogroup /dragon/medianew; chmod 0555 /dragon/medianew
```

### Phase 2: Move one subdirectory at a time

Two-pass per subdir (copy → verify → delete source):

```bash
# For each subdir (manuals → movies → tvshows → ...):
doas rsync -aHAX --info=progress2 /dragon/media/<sub>/ /dragon/medianew/<sub>/
# Verify file count + byte size match:
find /dragon/media/<sub> -type f | wc -l
find /dragon/medianew/<sub> -type f | wc -l
du -sb /dragon/media/<sub> /dragon/medianew/<sub>
# Then delete source:
doas rm -rf /dragon/media/<sub>
```

Two-pass (copy, verify, delete) not `--remove-source-files` because:
- No snapshots → no rollback if verify fails after deletion.
- Peak space overhead = one subdir's size (biggest 4.7T, fits in 7T free).
- `rm -rf` on a no-snapshot dataset reclaims space instantly.

### Phase 3: Rename dataset, set up photos

```bash
doas rmdir /dragon/media            # now empty
doas zfs rename dragon/medianew dragon/media
# Snap mountpoint perms back to match original:
chown nobody:nogroup /dragon/media; chmod 0555 /dragon/media
# Create photos subdir (owned by scott:users for syncthing):
mkdir /dragon/media/photos
chown scott:users /dragon/media/photos
# Stop syncthing, move photos data in:
doas systemctl stop syncthing.service
rsync -aHAX /dragon/photos/ /dragon/media/photos/  # as root, -a preserves scott:users
doas zfs destroy dragon/photos
```

### Phase 4: Nix + AGENTS.md updates

- 2 lines in `configuration.nix` (syncthing path + firesafe path).
- AGENTS.md photos pipeline section.
- No Mac-side changes (folder id unchanged).

### Phase 5: Rebuild + verify

```bash
git push origin && git push sophrosyne
ssh -t sophrosyne "cd ~ && git pull && nr"
systemctl status syncthing.service
```

### Operational notes
- **Samba:** Stop `smbd` during migration (content shrinks then reappears).
- **Firesafe:** Don't plug in USB drive during migration.
- **Pool is DEGRADED** — the 8.7T of reads+writes would be slower (no
  parallelism from offline device) and add ~8.7T of SSD write wear.

## Why it was deferred

The motivating change (move photos under `/dragon/media`) was achieved with a
simple `zfs set mountpoint=/dragon/media/photos dragon/photos` — zero I/O,
seconds of work. Promoting `/dragon/media` itself to a dataset would require
rewriting 8.7T on a degraded pool, adding years of SSD wear for the cosmetic
benefit of having `dragon/media` as a dataset. The existing directory structure
on the `dragon` root dataset serves Samba, firesafe, and rsync access without
issues.
