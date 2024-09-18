{ pkgs ? import <nixpkgs> {} }:

pkgs.stdenv.mkDerivation {
  pname = "vuclient";
  version = "0.0.3"; 

  src = pkgs.fetchFromGitHub {
    owner = "bonds";
    repo = "vuclient";
    rev = "main";
    sha256 = "sha256-kd/L3QQL/tCxU655NJtwMOojUEaisdSHk8ytCpCxoNA";
  };

  buildInputs = [ pkgs.fish pkgs.wget ];

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

