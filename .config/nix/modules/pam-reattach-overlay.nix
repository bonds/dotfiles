final: prev: {
  pam-reattach = prev.pam-reattach.overrideAttrs (old: {
    postFixup =
      (old.postFixup or "")
      + ''
        install_name_tool -change ${prev.openpam}/lib/libpam.2.dylib /usr/lib/libpam.2.dylib $out/lib/pam/pam_reattach.so
        codesign -f -s - $out/lib/pam/pam_reattach.so
      '';
  });
}
