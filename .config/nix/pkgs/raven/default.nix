{
  lib,
  pkgs,
  python3,
}: let
  pname = "raven";
  version = "0.2.3";
  # a2a-sdk: nixpkgs 26.05 ships 0.3.26 but raven 0.2.3 needs >=1.1.2
  # (imports a2a.utils.TransportProtocol, added in the 1.x series). Override
  # with the 1.1.2 sdist from PyPI.
  a2aSdk = python3.pkgs.a2a-sdk.overridePythonAttrs (old:
    old
    // rec {
      version = "1.1.2";
      src = pkgs.fetchurl {
        name = "a2a_sdk-1.1.2.tar.gz";
        url = "https://files.pythonhosted.org/packages/38/cc/59b35c518d8289bd59d20d9d216ca29ccb41c4697eb85971efe41d1adaf3/a2a_sdk-1.1.2.tar.gz";
        sha256 = "045xl4q0x6rv7hipy3n7hl555f614r9bsn42xrrs9h0dkazxha7r";
      };
      # 1.1.2 imports `jsonrpc` (PyPI json-rpc) — not in 0.3.26's dep list.
      propagatedBuildInputs = (old.propagatedBuildInputs or []) ++ [python3.pkgs.json-rpc];
      doCheck = false;
      dontCheckRuntimeDeps = true;
    });
  # EverMind-AI Raven — AI-native CLI agent. Distributed via GitHub release
  # assets only (NOT on PyPI: the `raven` name there belongs to the legacy
  # Sentry client). Built from the release WHEEL, which (unlike the sdist)
  # ships the prebuilt web UI at raven/ui/dist/index.html — the sdist lacks
  # it, which made `raven` print "No page is built".
  # The src name MUST keep the .whl extension: pypaInstallPhase only installs
  # dist/*.whl, so a nameless fetch silently installs nothing (the bug in the
  # first wheel attempt).
  wheel = pkgs.fetchurl {
    name = "${pname}-${version}-py3-none-any.whl";
    url = "https://github.com/EverMind-AI/Raven/releases/download/v0.2.3/raven-0.2.3-py3-none-any.whl";
    sha256 = "0m3qk7sa3zlmnf9sl3pbwssy3sg863wvhvfj6lcway0xbzk9sgc5";
  };
in
  python3.pkgs.buildPythonApplication {
    inherit pname version;
    src = wheel;
    format = "wheel";

    # All base deps resolved from nixpkgs 26.05 python3Packages (Python 3.13).
    # Version pin notes vs the wheel's Requires-Dist ranges (nix doesn't
    # enforce those, but flagging what we knowingly deviate on):
    #   - lancedb 0.32.0 (wheel wants >=0.33) — 26.05 ships 0.32.0, and raven
    #     imports it lazily for raven.knowledge, so we ship what we have.
    #   - a2a-sdk 0.3.26 (wheel wants >=1.1.2) — 26.05 ships 0.3.26; kept for
    #     the same eager-import check to pass. TODO: revisit when 26.05 bumps.
    #   - protobuf 7.34.1 (wheel wants >=5.29.5,<7) — 26.05 ships 7.x; kept if
    #     the google.protobuf import works (a2a-sdk 0.3.x is fine with it).
    # ripgrep-bin is NOT a nixpkgs python3Packages attr; raven shells out to
    # `rg` via shutil.which with a pure-Python fallback, so rg on PATH (the
    # darwin system already has ripgrep) covers it.
    propagatedBuildInputs = with python3.pkgs; [
      typer
      litellm
      pydantic
      pydantic-settings
      httpx
      loguru
      rich
      croniter
      pyyaml
      prompt-toolkit
      json-repair
      tiktoken
      questionary
      watchfiles
      tomli-w
      idna
      portalocker
      mcp
      orjson
      numpy
      pillow
      qrcode
      lancedb
      aiohttp
      click
      pyarrow
      a2aSdk
      protobuf
      lxml
    ];

    doCheck = false;
    dontCheckRuntimeDeps = true;
    pythonImportsCheck = ["raven"];

    # `raven web` spawns the gateway as a detached child via
    # subprocess.Popen([sys.executable, "-P", "-m", "raven", ...]) — a BARE
    # store python3 that inherits only the env. The wrapper's own sys.path
    # surgery (site.addsitedir) is in-process and does not reach children, so
    # the child dies with "No module named raven" (see ~/.raven/web.log).
    # Export the same site-packages as PYTHONPATH so every descendant finds raven.
    makeWrapperArgs = [
      "--set"
      "PYTHONPATH"
      # raven's own site-packages (the out dir) first, then every propagated
      # dep's — see the comment above about the detached gateway child.
      ("$out/${python3.pkgs.python.sitePackages}"
        + ":"
        + python3.pkgs.makePythonPath (with python3.pkgs; [
          typer
          litellm
          pydantic
          pydantic-settings
          httpx
          loguru
          rich
          croniter
          pyyaml
          prompt-toolkit
          json-repair
          tiktoken
          questionary
          watchfiles
          tomli-w
          idna
          portalocker
          mcp
          orjson
          numpy
          pillow
          qrcode
          lancedb
          aiohttp
          click
          pyarrow
          a2aSdk
          protobuf
          lxml
        ]))
    ];

    meta = with lib; {
      description = "Raven — AI-native command line agent with memory, proactivity, context control, and skill evolution";
      homepage = "https://github.com/EverMind-AI/Raven";
      license = licenses.asl20;
      mainProgram = "raven";
      maintainers = [];
    };
  }
