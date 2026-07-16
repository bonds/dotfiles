vudials: pkgs: rec {
  vuserver = pkgs.callPackage "${vudials}/pkgs/vuserver" {};
  vuclient = pkgs.callPackage "${vudials}/pkgs/vuclient" {};
}
