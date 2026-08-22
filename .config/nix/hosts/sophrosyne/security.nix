{
  config,
  pkgs,
  ...
}: let
  userHome = config.users.users.scott.home;
in {
  security.doas.extraRules = [
    {
      users = ["scott"];
      persist = true;
    }
    {
      users = ["scott"];
      cmd = "/run/current-system/sw/bin/nixos-rebuild";
      noPass = true;
    }
    {
      users = ["scott"];
      cmd = "/run/current-system/sw/bin/nh";
      noPass = true;
    }
    {
      users = ["scott"];
      cmd = "/run/current-system/sw/bin/systemctl";
      noPass = true;
    }
    {
      users = ["scott"];
      cmd = "/run/current-system/sw/bin/journalctl";
      noPass = true;
    }
  ];

  security.pam.sshAgentAuth.enable = true;
  security.pam.sshAgentAuth.authorizedKeysFiles = [
    "/etc/ssh/authorized_keys.d/scott"
  ];

  system.activationScripts.doasPamAuthKeys.text = ''
    install -D -m 0444 -o root -g root \
      ${userHome}/.config/ssh/keys \
      /etc/ssh/authorized_keys.d/scott
  '';

  system.activationScripts.bareRepoHooks.text = ''
    if [ -d "${userHome}/.config/dotfiles" ]; then
      ${pkgs.git}/bin/git --git-dir="${userHome}/.config/dotfiles" config core.hooksPath "${userHome}/.config/git/hooks" || true
    fi
  '';

  system.activationScripts.photoRsyncKey.text = ''
    # Deploy the photo-rsync SFTP-restricted key to the photo-backup service
    # account so SFTP (photo-export) authenticates as photo-backup, who OWNS
    # /dragon/media/photos. sshd's AuthorizedKeysFile includes ~/.ssh/authorized_keys.
    # restrict + command=sftp-server -d confines the key to SFTP photo writes.
    PHOTO_KEY="${userHome}/Documents/.config/photo-rsync-key.pub"
    SFTP_CMD='${pkgs.openssh}/libexec/sftp-server -d /dragon/media/photos'
    PB_KEYS="/home/photo-backup/.ssh/authorized_keys"
    # NOTE: every step is guarded with || true so this snippet NEVER aborts
    # activation on a re-run (NixOS's `trap ERR` turns any non-zero step into a
    # failed snippet -> 'Failed to run activate script', exit 2). Works are
    # idempotent once applied.
    if [ -f "''$PHOTO_KEY" ]; then
      mkdir -p /home/photo-backup/.ssh || true
      # OpenSSH strict-mode requires the user to own home/.ssh.
      chown photo-backup:users /home/photo-backup 2>/dev/null || true
      chown photo-backup:users /home/photo-backup/.ssh 2>/dev/null || true
      chmod 0700 /home/photo-backup/.ssh 2>/dev/null || true
      KEY_CONTENT="''$(cat ''$PHOTO_KEY)"
      # rebuild authorized_keys idempotently (replace any prior photo-rsync line)
      { grep -v "photo-rsync@accismus" "''$PB_KEYS" 2>/dev/null || true; } > /tmp/ak_clean
      printf 'restrict,command="%s" %s\n' "''$SFTP_CMD" "''$KEY_CONTENT" >> /tmp/ak_clean
      install -m 0644 -o photo-backup -g users /tmp/ak_clean "''$PB_KEYS" 2>/dev/null || true
      rm -f /tmp/ak_clean || true
      echo "photo-rsync: deployed SFTP-restricted key -> photo-backup/.ssh/authorized_keys" >&2
    else
      echo "photo-rsync: no key found at ''$PHOTO_KEY — has accismus run nr yet?" >&2
    fi
    # guard EVERY path so the snippet's final exit is always 0
    :
  '';

  system.activationScripts.checkMissingPhotoKey.text = ''
    if [ ! -f ${userHome}/Documents/.config/photo-rsync-key.pub ]; then
      echo "WARNING: photo-rsync-key.pub missing — run nr on accismus first" >&2
    fi
  '';

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.login1.suspend" ||
            action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||
            action.id == "org.freedesktop.login1.hibernate" ||
            action.id == "org.freedesktop.login1.hibernate-multiple-sessions")
        {
            return polkit.Result.NO;
        }
    });
  '';
}
