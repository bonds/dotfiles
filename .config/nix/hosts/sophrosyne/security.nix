{
  config,
  pkgs,
  lib,
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

  system.activationScripts.checkSecrets = {
    text = ''
      warn_missing() {
        echo "WARNING: $1 is missing!" >&2
        echo "  Purpose: $2" >&2
        echo "  Source: $3" >&2
      }

      if [ ! -f /etc/ddns-token ]; then
        warn_missing \
          /etc/ddns-token \
          "DNSimple API token for DDNS (updates home.ggr.com A record)" \
          "Bitwarden vault entry: \"home.ggr.com dns token\""
      fi

      if [ ! -f /etc/email-pass ]; then
        warn_missing \
          /etc/email-pass \
          "Gmail app password for msmtp (system emails, ZED alerts)" \
          "Bitwarden vault entry: \"server email account\""
      fi

      if [ ! -f /var/lib/dst-server/cluster_token.txt ]; then
        warn_missing \
          /var/lib/dst-server/cluster_token.txt \
          "Klei cluster token for Don't Starve Together server" \
          "Copy from /dragon/containers/dontstarve/DoNotStarveTogether/Cluster_1/cluster_token.txt"
      fi

      if [ ! -f ${userHome}/Documents/.config/photo-rsync-key.pub ]; then
        warn_missing \
          ${userHome}/Documents/.config/photo-rsync-key.pub \
          "Photo rsync SSH public key from accismus — needed for automated nightly photo backup" \
          "Run nr on accismus first (generates the key), then wait for Syncthing to sync Documents/, then rebuild sophrosyne"
      fi
    '';
  };

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
