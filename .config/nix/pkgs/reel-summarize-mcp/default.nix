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
in
  python3.pkgs.buildPythonApplication {
    pname = "reel-summarize-mcp";
    version = "0.1.0";
    src = ./.;
    format = "pyproject";

    nativeBuildInputs = with python3.pkgs; [setuptools wrapPython];

    propagatedBuildInputs = with python3.pkgs; [mcp httpx starlette uvicorn] ++ [reelSummarize];

    dontUsePythonRuntimeDepsCheck = true;

    makeWrapperArgs = [
      "--set"
      "TRANSCRIBE_LIBRARY"
      "${transcribeCpp}/lib/${
        if stdenv.hostPlatform.isDarwin
        then "libtranscribe.dylib"
        else "libtranscribe.so"
      }"
      "--prefix"
      "PATH"
      ":"
      (lib.makeBinPath [yt-dlp ffmpeg])
    ];

    meta = with lib; {
      description = "MCP server that summarizes Instagram Reels using local models";
      homepage = "https://github.com/bonds/dotfiles";
      license = licenses.mit;
      platforms = platforms.unix;
      mainProgram = "reel-summarize-mcp";
    };
  }
