{
  lib,
  rustPlatform,
  fetchFromGitHub,
  python3,
}: let
  version = "0.1.4";
in
  rustPlatform.buildRustPackage {
    pname = "oxillama";
    inherit version;

    src = fetchFromGitHub {
      owner = "cool-japan";
      repo = "oxillama";
      rev = "v${version}";
      hash = "sha256-rD3DBTye7GjdatWzfG+VfWmqJcEQ2hzkd2IxufsW+hA=";
    };

    cargoLock.lockFile = ./Cargo.lock;

    nativeBuildInputs = [python3];

    postUnpack = ''
      cp ${./Cargo.lock} source/Cargo.lock
    '';

    # Pure Rust build — no C compiler, system libs, or GPU deps needed.
    # The "server" feature is on by default so `oxillama serve` is available.
    buildFeatures = [];

    doCheck = false;

    meta = {
      description = "Pure Rust LLM inference engine — a sovereign alternative to llama.cpp";
      longDescription = ''
        Oxillama provides GGUF model loading, multi-format quantized inference,
        and an OpenAI-compatible API server — all without any C, C++, or Fortran.
        Subcommands: run (interactive), serve (HTTP API), info (model metadata).
      '';
      homepage = "https://github.com/cool-japan/oxillama";
      license = lib.licenses.asl20;
      platforms = ["aarch64-darwin"];
      mainProgram = "oxillama";
      maintainers = [];
    };
  }
