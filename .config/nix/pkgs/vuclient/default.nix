{ pkgs ? import <nixpkgs> {} }:

pkgs.stdenv.mkDerivation {
  pname = "vuclient";
  version = "0.0.7"; 

  src = pkgs.fetchFromGitHub {
    owner = "bonds";
    repo = "vuclient";
    rev = "main";
    hash = "sha256-+loCWpobOuuOMpTF5/ppz6/wCAK1VS3oteoTjVfney0=";
  };

  installPhase = ''
    mkdir -p $out/bin
    cp $src/vuclient $out/bin/vuclient
    chmod +x $out/bin/vuclient
  '';

  meta = with pkgs.lib; {
    description = "A script that samples perf stats and sends them to a vuserver driving VU1 dials.";
    license = licenses.mit; 
    platforms = platforms.linux;
  };
}

