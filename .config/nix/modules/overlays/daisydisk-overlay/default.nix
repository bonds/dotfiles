final: prev: {
  daisydisk = final.mkDarwinPackage {
    pname = "daisydisk";
    version = "4.34.2";

    src = prev.fetchurl {
      url = "https://daisydiskapp.com/download/DaisyDisk.zip";
      hash = "sha256-Re9GOfK03Gogb4Ep1itUJm60L94qvGfXgjqpLg8GQlc=";
    };

    nativeBuildInputs = [prev.unzip];

    installPhase = ''
      mkdir -p $out/Applications
      cp -r DaisyDisk.app $out/Applications/
    '';

    meta = {
      description = "Disk usage visualizer with a pie chart interface";
      homepage = "https://daisydiskapp.com";
      license = prev.lib.licenses.unfree;
    };
  };
}
