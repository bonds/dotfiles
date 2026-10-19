---
name: machines-and-services
description: "Per-machine setup and services: accismus (Syncthing, photo-export and the nightly photos backup), sophrosyne (ZFS pool, firesafe USB backup and its tools, photos pipeline, Minecraft Bedrock, Don't Starve Together, Nitter, temperature logging, doas/sudo privilege), metanoia. Use for anything involving those machines, their disks, backups, doas or sudo prompts, or long-running services."
---

Paths below are relative to `.config/nix/` unless absolute. The bare-repo
dotfiles workflow is described in `~/AGENTS.md`.

### doas (sophrosyne)

Layered privilege: `noPass` rules for `systemctl`, `journalctl`,
`nixos-rebuild` and `nh` (no PAM, no TouchID), and `pam_ssh_agent_auth` for
everything else, which challenges the forwarded SSH agent (Secretive on
accismus) — expect one TouchID prompt per operation.

- **Rule matching needs the full path.** `doas
  /run/current-system/sw/bin/systemctl restart syncthing`, never `doas
  systemctl …`: doas does not resolve bare names through `PATH` before matching.
- **`args` is an exact match** on the whole argument list, not a prefix, so
  `args restart` only matches `doas cmd restart` with nothing after it. All
  current noPass rules are therefore scoped to the command only.
- **Agent forwarding is required** for the TouchID path; SSH config sets
  `ForwardAgent yes` for sophrosyne. Without it doas falls back to a password
  prompt, which only works interactively.
- The `pam_ssh_agent_auth` key file is `/etc/ssh/authorized_keys.d/scott`
  (root-owned, outside the nix store — activation copies it on each switch to
  avoid group-writable `/nix/store` directory rejections).
- Passwordless does not mean agent-run: activating rebuilds are Scott's to run
  (see `~/AGENTS.md` → Conventions).

### Machines
Three machines managed from this repo:
- **accismus** — macOS laptop (aarch64-darwin, nix-darwin)
  - **Dotfiles** use the bare-repo approach described in ~/AGENTS.md (`~/.local/share/dotfiles`, moved from `~/.config/dotfiles` on 2026-10-11). The `config` fish alias is defined in `~/.config/fish/conf.d/10-aliases.fish`.
  - **Syncthing** managed via nix-darwin launchd agent (not standalone app). Declarative `config.xml` generated and deployed by activation script. Config dir at `~/Library/Application Support/Syncthing/`. Preserves `key.pem`, `cert.pem`, `index-v2/` across rebuilds.
  - **Photos backup** via `photos-backup` launchd agent (daily at 2am). Runs **`photo-export`** (PhotoKit-native Swift) which streams ALL assets (local + iCloud-only) over **SFTP** to `/dragon/media/photos` as `photo-backup` — no SMB mount, no local copies, basic XMP sidecars. No osxphotos, no Syncthing for photos.
    - **⚠️ Prerequisite:** Photos access grant — see `pkgs/photokit-export/FIRST-RUN.md`. One-time "Allow" click via `open`; re-grant after any binary change (new nix build / version bump).
    - **iCloud originals:** with "Optimize Mac Storage" enabled, originals are iCloud-only; `photo-export` fetches them via PhotoKit (`PHImageManager.requestImageDataAndOrientation`), no AppleScript.
    - **Resumable:** `~/.cache/photo-export-manifest.txt` tracks completed UUIDs; `yyyy/mm` date dirs; atomic `.part`+rename.
    - **Safety guard:** `photo-export` refuses to write when dest is the SMB mount path but isn't actually mounted (prevents silent local-disk writes).
- **metanoia** — NixOS workstation (x86_64-linux)
  - **Dotfiles:** Should be migrated to the bare-repo approach when back online (same as accismus/sophrosyne).
- **sophrosyne** — NixOS server at `sophrosyne.local` / `home.ggr.com` (x86_64-linux)
  - **Dotfiles** use the same bare-repo approach. Remote push target for this machine: `scott@home.ggr.com:~/.local/share/dotfiles`. The bare repo has a `post-receive` hook at `~/.local/share/dotfiles/hooks/post-receive` (installed manually during bootstrap; tracked in the repo at `.config/git/hooks/post-receive` and pointed to via `core.hooksPath`) that checks out the work tree to `$HOME` on each push to `main`.
  - **mDNS name can come back as `sophrosyne-2.local`:** avahi renames itself when its startup probe is answered, and a rebuild that restarts `avahi-daemon` is enough to trigger it (the outgoing instance's records answer the new one's probe). Nothing actually owns `sophrosyne.local` in that case, and the suffix sticks until the daemon restarts again. Fix: `ssh sophrosyne 'doas /run/current-system/sw/bin/systemctl restart avahi-daemon'`, then confirm the journal says `Host name is sophrosyne.local`. Symptom to recognise: `ping sophrosyne-2.local` resolves to 192.168.4.43 while `sophrosyne.local` does not.
  - **ZFS pool:** The `dragon` pool is intentionally degraded (raidz2, 1 device kept offline) — running on 1-disk redundancy by design.
  - **Temperature logging:** NVMe/CPU temps and fan speeds are logged every minute to `/dragon/logs/temps.log` via `log-temps.timer`. After a crash or lockup, check the last entries in this file to see if temps spiked before the failure. The log survives reboots since it's on the ZFS pool.
  - **Firesafe USB backup:** Automated off-site backup via an A/B USB drive rotation. Defined in `modules/firesafe-backup.nix` (NixOS module: `programs.firesafe-backup`).
    - **How it works:** A udev rule matches drives labeled `firesafe` and triggers `firesafe-backup.service`, which mounts at `/mnt/firesafe`, reads `.firesafe-id` (A or B), then rsyncs configured sources (Archive, Backups, Documents, Media/* subdirs, Photos) from `/dragon/`.
    - **Deleted file preservation:** Rsync uses `--backup --backup-dir=.deleted/DATE/`. When drive free space drops below 50GB, the oldest `.deleted/` dirs are pruned (one at a time) until the threshold is met.
    - **A/B rotation:** Each drive has a `.firesafe-id` file (A or B). Rotate weekly by swapping drives to always have an off-site copy.
    - **Commands:**
      - `firesafe-status` — mount status, elapsed time, source-count ETA, log tail
      - `firesafe-status -w` — live-updating every 2s
      - `firesafe-eject` — kills backup, syncs, unmounts (uses sudo)
      - `firesafe-reclaim [--dry-run]` — prune `.deleted/` dirs
      - `firesafe-deleted [date]` — browse `.deleted/` contents
    - **Deleted file changelog:** A permanent record of all deleted files (not pruned) is appended to `/dragon/logs/firesafe-backup-changelog.log` on each backup run. The log survives drive rotation and `.deleted/` cleanup. Format: `DATE<tab>SOURCE_PATH`. View with `tail /dragon/logs/firesafe-backup-changelog.log`.
    - **Email notifications:** Results sent via msmtp to scott@ggr.com on completion/failure.
    - **First-time setup:** Label ext4 drive `firesafe` (`e2label`), create `.firesafe-id`, plug in to trigger backup. Drive must be 4.5TB+ to hold Archive + Backups + Documents + selected Media subdirs.
    - **Drive I/O note:** The WD Game Drive USB bridge (1058:262f) is BOT-only, QD=1, no UASP — USB-native PCB, cannot shuck. Random I/O ~1 MB/s; sequential ~40-90 MB/s ext4. ext4 journal vs exFAT speed tradeoffs, dirty page flush hang on umount. See `firesafe-backup.nix` header comment for full details.
  - **Photos pipeline:**
    - Mac (accismus): `photos-backup` launchd agent runs nightly at 2am — runs **`photo-export`** (PhotoKit-native) which streams ALL assets over **SFTP** to `/dragon/media/photos` (photo-backup key). No SMB mount, no osxphotos, no rsync, no syncthing for photos.
    - SMB share: `[photos]` in `services.samba` (see `hosts/sophrosyne/networking.nix`) → `valid users = photo-backup`, path `/dragon/media/photos`. Samba user `photo-backup` (uid 973) has a password in `pdbedit`; not a shell login.
    - Storage: `/dragon/media/photos` on sophrosyne (ZFS dataset `dragon/photos`, `atime=off`)
    - Firesafe: `Photos` source picks up `/dragon/media/photos` during backup
    - ZFS dataset: `dragon/photos` mounted at `/dragon/media/photos`, `atime=off`. Files are upserted by UUID manifest (no `--delete` mirroring; deleted originals in Photos are not "deleted" from the backup — firesafe `.deleted/` note no longer applies to photos).
    - **Archived plan:** A larger restructure (promoting `/dragon/media` itself to a dataset) was researched but deferred — see `.config/nix/media-dataset-restructure-plan.md` for context.
  - **Minecraft Bedrock server: Native (no container) via `modules/minecraft-bedrock.nix`.
    - Binary packaged at `pkgs/bedrock-server/` — `fetchurl` from Mojang, `autoPatchelfHook` for glibc compat.
    - Data dir: `/dragon/servers/minecraft` (migrated from old `/dragon/containers/minecraft`, kept as backup until `/dragon/containers` dataset was removed).
    - Runs as `minecraft` user, systemd service with FIFO console socket for graceful stop.
    - **Updates:** `nr --update` on Linux auto-bumps via `pkgs/bedrock-server/update.sh` (queries kittizz tracker, downloads zip, computes sha256, rewrites `default.nix`).
  - **Don't Starve Together server:** Native (no container) via `modules/dst-server.nix`.
    - Binary installed via SteamCMD at `/dragon/servers/dontstarve/install/` (app ID 343050, auto-updates on start).
    - Old Debian library shims (`libcurl-gnutls`, `libnettle6`, `libldap-2.4`, `libsasl2`) extracted from Debian snapshots for ABI compatibility.
    - Dual-shard setup (Master + Caves) as two systemd services.
    - Config templates + non-destructive config generation in `modules/dst-server-config/`.
    - Token at `/var/lib/dst-server/cluster_token.txt` (warn_missing in checkSecrets).
  - **Nitter service** (Twitter/X alt front-end, via `services.nitter` in configuration.nix):
    - Listens on port **8282**, reachable over Tailscale only (8282 added to `networking.firewall.interfaces.tailscale0.allowedTCPPorts` in `networking.nix` — never LAN/public).
    - The module auto-provisions a local Redis (`redis-nitter.service`) for the tweet cache.
    - **LoadCredential gotcha:** the unit does `LoadCredential=sessionsFile:/var/lib/nitter/sessions.jsonl`, and systemd refuses to mount a credential whose source file doesn't already exist (`Failed at step CREDENTIALS` → crash-loop). The module never creates the file, so provision it via `systemd.tmpfiles.rules` (see the comment in configuration.nix) — `d /var/lib/private/nitter` + `f .../sessions.jsonl` (DynamicUser StateDirectory). Empty file is fine.
    - **Reality caveat:** X rate-limits aggressively; persistent 429s are X's fault, not the deployment — may not be worth fighting.
