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
    # Note: quoted heredoc delimiter ('WRAPPER') so $SSH_ORIGINAL_COMMAND below is
    # NOT expanded by the activation shell — it must reach the wrapper verbatim and
    # expand only at runtime (when ssh invokes the wrapper on the server).
    # The sftp-server path is nix-interpolated (${pkgs.openssh}) at eval time.
    cat > /usr/local/bin/rrsync-photos << 'WRAPPER'
    #!/bin/sh
    # Restricted transport for the photo backup key (photo-rsync@accismus).
    # Allows ONLY:
    #   1. rsync to /dragon/media/photos/   (the nightly's rsync path)
    #   2. sftp confined to /dragon/media/photos/ (photo-export streaming upload,
    #      launchd at 2am; libssh2 requests the sftp subsystem, arriving here as
    #      SSH_ORIGINAL_COMMAND="sftp")
    # Everything else is rejected.
    case "''$SSH_ORIGINAL_COMMAND" in
      *rsync*--server*/dragon/media/photos/*)
        exec "''$SSH_ORIGINAL_COMMAND"
        ;;
      sftp)
        # -d confines sftp to the photos dir (removes relative-up escapes)
        exec "${pkgs.openssh}/libexec/sftp-server" -d /dragon/media/photos
        ;;
      *)
        echo "REJECTED: this key is restricted to rsync/sftp /dragon/media/photos/ only" >&2
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
