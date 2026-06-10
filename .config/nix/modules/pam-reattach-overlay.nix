final: prev: {
  pam-reattach = prev.pam-reattach.overrideAttrs (old: {
    postInstall =
      (old.postInstall or "")
      + ''
        install_name_tool -change ${prev.openpam}/lib/libpam.2.dylib /usr/lib/libpam.2.dylib $out/lib/pam/pam_reattach.so
      '';
  });
}
