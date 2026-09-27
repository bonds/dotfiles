{
  lib,
  stdenv,
  python3,
  callPackage,
  yt-dlp,
  ffmpeg,
}: let
  # These live in the flake's pkgs/ tree but are only exposed to `pkgs` via the
  # darwin overlay. `callPackage` them locally so this derivation also builds on
  # NixOS (sophrosyne) without depending on that overlay.
  transcribeCpp = callPackage ../transcribe-cpp {};
  transcribeCppPython = callPackage ../transcribe-cpp-python {transcribe-cpp = transcribeCpp;};
  reelSummarize = callPackage ../reel-summarize {
    transcribe-cpp = transcribeCpp;
    transcribe-cpp-python = transcribeCppPython;
  };
  # Hermetic laya (line-salience pre-filter) + its English checkpoint.  laya
  # needs torch-bin (x86_64-linux only), so this whole MCP package is linux-
  # scoped (it runs on sophrosyne).  Reading LAYA_CHECKPOINT_DIR at runtime
  # lets stages/laya.py load the checkpoint straight from the store; the code
  # import-guards so an absent laya/checkpoint never breaks the service.
  laya = callPackage ../laya {
    inherit (python3.pkgs) buildPythonPackage fetchPypi;
    python3 = python3;
    torch-bin = python3.pkgs.torch-bin;
  };
  layaCheckpoint = callPackage ../laya-checkpoint {};
in
  python3.pkgs.buildPythonApplication {
    pname = "reel-summarize-mcp";
    version = "0.1.0";
    src = ./.;
    format = "pyproject";

    nativeBuildInputs = with python3.pkgs; [setuptools wrapPython];

    propagatedBuildInputs =
      (with python3.pkgs; [mcp httpx starlette uvicorn])
      ++ [reelSummarize laya];

    dontUsePythonRuntimeDepsCheck = true;

    makeWrapperArgs = [
      "--set"
      "TRANSCRIBE_LIBRARY"
      "${transcribeCpp}/lib/${
        if stdenv.hostPlatform.isDarwin
        then "libtranscribe.dylib"
        else "libtranscribe.so"
      }"
      "--set"
      "LAYA_CHECKPOINT_DIR"
      "${layaCheckpoint}"
      "--prefix"
      "PATH"
      ":"
      (lib.makeBinPath [yt-dlp ffmpeg])
    ];

    meta = with lib; {
      description = "MCP server that summarizes Instagram Reels using local models";
      homepage = "https://github.com/bonds/dotfiles";
      license = licenses.mit;
      platforms = platforms.linux; # torch-bin / laya are linux/x86_64
      mainProgram = "reel-summarize-mcp";
    };
  }
