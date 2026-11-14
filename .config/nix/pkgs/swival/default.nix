{
  lib,
  stdenv,
  fetchurl,
  python313,
  makeWrapper,
  autoPatchelfHook,
  zlib,
  openssl,
}:
# Swival is a pure-Python CLI whose dependency closure (litellm, boto3,
# google-cloud-aiplatform, tiktoken, ...) is far ahead of nixpkgs and mostly
# binary-wheel-only, so it is packaged the way `uv tool install swival`
# installs it: the exact wheel set is vendored in sources.nix and unzipped
# here. No python build backend, no compilation, no network.
#
# sources.nix is generated — run `bash pkgs/swival/update.sh` (which `nr
# --update` does) instead of editing it. The pinned python minor version lives
# in generate.py (PYTHON_VERSION) and must match `python313` below.
let
  # pip only unpacks the vendored wheels here (--no-deps --no-index), so it is
  # a build-time tool, not a runtime dependency.
  python = python313.withPackages (ps: [ps.pip]);
  sources = import ./sources.nix;
  system = stdenv.hostPlatform.system;
  wheelNames =
    sources.wheels.${system}
      or (throw "swival: no vendored wheels for ${system} — add it to PLATFORMS in pkgs/swival/generate.py");
  wheel = name: fetchurl {inherit (sources.files.${name}) url sha256;};
  wheels = map wheel wheelNames;
in
  stdenv.mkDerivation {
    pname = "swival";
    inherit (sources) version;

    dontUnpack = true;
    dontBuild = true;
    # Wheels are already stripped upstream, and macOS `strip -S` mangles the
    # non-Mach-O files in them: it rewrites litellm's 4.5 KB favicons as 808 MB
    # (and 539 MB for the two other icons), taking the output from 417 MB to
    # 1.7 GB. Nothing here is a Mach-O we built, so there is nothing to strip.
    dontStrip = true;

    nativeBuildInputs =
      [makeWrapper]
      ++ lib.optionals stdenv.hostPlatform.isLinux [autoPatchelfHook];

    # Only consulted by autoPatchelfHook. Wheels are built against a generic
    # glibc and dlopen their own .so files, so on NixOS the C++ runtime has to
    # be baked into their rpath here; on darwin there is nothing to patch.
    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      stdenv.cc.cc.lib
      zlib
      openssl
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/swival $out/bin wheels

      # Unpack with pip rather than `unzip`, because pip is what `uv tool
      # install swival` does and it applies the wheel spec: `.data` directories
      # are moved into place and exec bits preserved. Plain unzip leaves
      # `jmespath-1.1.0.data/` sitting in site-packages. Either way it is
      # `--no-deps --no-index`: no resolution, no network.
      #
      # pip parses the *filename* of each argument, and a store path is
      # <hash>-<wheel>.whl, so link them back to their real names first.
      ${lib.concatStrings (lib.zipListsWith (name: path: ''
          ln -s ${path} "wheels/${name}"
        '')
        wheelNames
        wheels)}
      ${python}/bin/python -m pip install \
        --no-deps --no-index --no-cache-dir --no-compile --quiet \
        --target "$out/lib/swival" \
        wheels/*.whl

      # pip's console scripts land in $out/lib/swival/bin with shebangs into
      # the build-time python; the wrapper below replaces them.
      rm -rf "$out/lib/swival/bin"

      # pip generates this from the wheel's entry_points.txt; the wrapper
      # needs a stable entry point to exec.
      cat > $out/lib/swival/_swival_entry.py <<'EOF'
      import sys

      from swival.agent import main

      sys.exit(main())
      EOF

      makeWrapper ${python313}/bin/python3 $out/bin/swival \
        --prefix PYTHONPATH : "$out/lib/swival" \
        --add-flags "$out/lib/swival/_swival_entry.py"

      runHook postInstall
    '';

    meta = {
      description = "CLI coding agent built to work reliably with smaller and local models";
      longDescription = ''
        Swival is a terminal coding agent with context management tuned for
        tight windows: output caps, agent-driven snapshots, graduated
        compaction, and think/todo state that survives compaction. Supports
        LM Studio, llama.cpp, HuggingFace, OpenRouter, Gemini/Vertex, ChatGPT
        subscriptions, Bedrock and any OpenAI-compatible server.
      '';
      homepage = "https://swival.dev/";
      license = lib.licenses.mit;
      platforms = ["aarch64-darwin" "x86_64-linux"];
      mainProgram = "swival";
      maintainers = [];
    };
  }
