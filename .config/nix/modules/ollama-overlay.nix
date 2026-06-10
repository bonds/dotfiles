final: prev: {
  ollama = prev.stdenvNoCC.mkDerivation {
    pname = "ollama";
    version = "0.30.7";

    src = prev.fetchurl {
      url = "https://github.com/ollama/ollama/releases/download/v0.30.7/ollama-darwin.tgz";
      hash = "sha256-+js4LkuQxZXh9HPG3yzR7K0nDE0EIl9rBp5bhqEPPTM=";
    };

    sourceRoot = ".";

    installPhase = ''
      mkdir -p $out/bin $out/lib/ollama
      cp ollama llama-server llama-quantize $out/lib/ollama/
      cp -r *.so *.dylib $out/lib/ollama/ 2>/dev/null || true

      ln -s $out/lib/ollama/ollama $out/bin/ollama
      ln -s $out/lib/ollama/llama-server $out/bin/llama-server
      ln -s $out/lib/ollama/llama-quantize $out/bin/llama-quantize
    '';

    dontStrip = true;

    meta = {
      description = "Get up and running with large language models locally";
      homepage = "https://github.com/ollama/ollama";
      license = prev.lib.licenses.mit;
      platforms = ["aarch64-darwin" "x86_64-darwin"];
      mainProgram = "ollama";
    };
  };
}
