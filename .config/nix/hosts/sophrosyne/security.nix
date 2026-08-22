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
    if [ -f "''$PHOTO_KEY" ]; then
      mkdir -p /home/photo-backup/.ssh
      # OpenSSH strict-mode requires the user to own their home/.ssh, or it
      # rejects authorized_keys ("Username/PublicKey combination invalid").
      chown photo-backup:users /home/photo-backup /home/photo-backup/.ssh
      chmod 0700 /home/photo-backup/.ssh
      KEY_CONTENT="''$(cat ''$PHOTO_KEY)"
      # remove old photo-rsync lines and append fresh (idempotent)
      if [ -f "''$PB_KEYS" ]; then
        grep -v "photo-rsync@accismus" "''$PB_KEYS" > /tmp/ak_clean 2>/dev/null
      else
        cp /dev/null /tmp/ak_clean
      fi
      printf 'restrict,command="%s" %s\n' "''$SFTP_CMD" "''$KEY_CONTENT" >> /tmp/ak_clean
      install -m 0644 -o photo-backup -g users /tmp/ak_clean "''$PB_KEYS"
      rm -f /tmp/ak_clean
      echo "photo-rsync: deployed SFTP-restricted key -> photo-backup/.ssh/authorized_keys" >&2
    else
      echo "photo-rsync: no key found at ''$PHOTO_KEY — has accismus run nr yet?" >&2
    fi
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
