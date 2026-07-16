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

  system.activationScripts.photoRsyncWrapper.text = ''
    mkdir -p /usr/local/bin
    cat > /usr/local/bin/rrsync-photos << 'WRAPPER'
    #!/bin/sh
    case "$SSH_ORIGINAL_COMMAND" in
      *rsync*--server*/dragon/media/photos/*)
        exec $SSH_ORIGINAL_COMMAND
        ;;
      *)
        echo "REJECTED: this key is restricted to rsync /dragon/media/photos/ only" >&2
        exit 1
        ;;
    esac
    WRAPPER
    chmod 755 /usr/local/bin/rrsync-photos
  '';

  system.activationScripts.photoRsyncKey.text = ''
    PHOTO_KEY="${userHome}/Documents/.config/photo-rsync-key.pub"
    if [ -f "$PHOTO_KEY" ]; then
      KEY_CONTENT=$(cat "$PHOTO_KEY")
      grep -v "photo-rsync@accismus" /etc/ssh/authorized_keys.d/scott > /tmp/authorized_keys_clean 2>/dev/null || true
      echo "restrict,from=\"192.168.4.*\",command=\"/usr/local/bin/rrsync-photos\" $KEY_CONTENT" >> /tmp/authorized_keys_clean
      install -m 0444 -o root -g root /tmp/authorized_keys_clean /etc/ssh/authorized_keys.d/scott
      rm -f /tmp/authorized_keys_clean
      echo "photo-rsync: deployed restricted key from accismus" >&2
    else
      echo "photo-rsync: no key found at $PHOTO_KEY — has accismus run nr yet?" >&2
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
