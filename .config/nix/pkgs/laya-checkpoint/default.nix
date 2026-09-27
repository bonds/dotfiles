{
  lib,
  stdenv,
  fetchurl,
}: let
  # convaiinnovations/laya English checkpoint (snapshot 55cf4c4).  These 5
  # files are the complete English model: ModernBERT-large encoder config, the
  # RL-agent head weights (model.safetensors), the agent config, and the
  # tokenizer.  Content hashes verified against ~/laya-bench/.hf-cache.
  base = "https://huggingface.co/convaiinnovations/laya/resolve/55cf4c4ebb4ebe31b2550e8bdf3bd21b99753851";

  # All five files fetched via fixed-output fetchurl (no network at build
  # time beyond these deterministic fetches).  The derivation assembles the
  # exact layout laya's Agent() loads from a local dir.
  files = [
    (fetchurl {
      url = "${base}/model.safetensors";
      hash = "sha256-iREC03Joj8KglNrFajhLxTe4fGPyH589rAvit8vI2Gw=";
    })
    (fetchurl {
      url = "${base}/rl_agent_config.json";
      hash = "sha256-rih7VrvPX4xPRUGunf0AyRTExIuUC4OYwwWK83upK70=";
    })
    (fetchurl {
      url = "${base}/encoder/config.json";
      hash = "sha256-vzq4BZj9zPQUhVos6A8ihZ5EktBsqKYt3Rz7Y5cviXk=";
    })
    (fetchurl {
      url = "${base}/tokenizer/tokenizer.json";
      hash = "sha256-bIqqmlQghPJFfqt3XU7rUfkqcMD9neKNXtsN3sPAjTA=";
    })
    (fetchurl {
      url = "${base}/tokenizer/tokenizer_config.json";
      hash = "sha256-UARN5g2qpz35fSYuFaQNT68BYOfXQt9ks3eHehMg3RI=";
    })
  ];
in
  stdenv.mkDerivation {
    pname = "laya-checkpoint";
    version = "55cf4c4";
    src = null;

    outputs = ["out"];

    buildInputs = [stdenv];
    dontBuild = true;

    installPhase = ''
      mkdir -p $out/encoder $out/tokenizer
      cp ${builtins.elemAt files 0} $out/model.safetensors
      cp ${builtins.elemAt files 1} $out/rl_agent_config.json
      cp ${builtins.elemAt files 2} $out/encoder/config.json
      cp ${builtins.elemAt files 3} $out/tokenizer/tokenizer.json
      cp ${builtins.elemAt files 4} $out/tokenizer/tokenizer_config.json
    '';

    # Fixed-output: hash of the assembled $out (matches the locally-assembled
    # directory content).
    outputHashMode = "recursive";
    outputHash = "sha256-y5bf1qkHc1G9Mx8LYqSyCTWdWaOglaiAIlroSLednKI=";
    outputHashAlgo = "sha256";

    meta = with lib; {
      description = "Laya English checkpoint (convaiinnovations/laya, ModernBERT-large)";
      homepage = "https://huggingface.co/convaiinnovations/laya";
      license = licenses.asl20;
      platforms = platforms.all;
    };
  }
