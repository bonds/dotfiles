final: prev: {
  pam-reattach = prev.pam-reattach.overrideAttrs (old: {
    postInstall =
      (old.postInstall or "")
      + ''
        OLD_PAM=$(otool -L "$out/lib/pam/pam_reattach.so" | grep "openpam" | awk '{print $1}')
        if [ -n "$OLD_PAM" ]; then
          echo "patching pam_reattach: $OLD_PAM -> /usr/lib/libpam.2.dylib"
          install_name_tool -change "$OLD_PAM" /usr/lib/libpam.2.dylib "$out/lib/pam/pam_reattach.so"
        fi
      '';
  });
}
