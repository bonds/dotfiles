final: prev: let
  mkDarwinPackage = import ../../lib/mkDarwinPackage.nix {inherit (prev) stdenvNoCC lib;};
in {
  ollama = mkDarwinPackage {
    pname = "ollama";
    version = "0.32.0";

    src = prev.fetchurl {
      url = "https://github.com/ollama/ollama/releases/download/v0.32.0/ollama-darwin.tgz";
      hash = "sha256-OxKknGxMuv1/+6XMumDL+AJ0zcIu6j6tecZGq6iIF0w=";
    };

    nativeBuildInputs = [];

    installPhase = ''
      mkdir -p $out/bin $out/lib/ollama
      cp ollama llama-server llama-quantize $out/lib/ollama/
      cp -r *.so *.dylib $out/lib/ollama/ 2>/dev/null || true

      ln -s $out/lib/ollama/ollama $out/bin/ollama
      ln -s $out/lib/ollama/llama-server $out/bin/llama-server
      ln -s $out/lib/ollama/llama-quantize $out/bin/llama-quantize
    '';

    meta = {
      description = "Get up and running with large language models locally";
      homepage = "https://github.com/ollama/ollama";
      platforms = ["aarch64-darwin" "x86_64-darwin"];
    };
  };
}
