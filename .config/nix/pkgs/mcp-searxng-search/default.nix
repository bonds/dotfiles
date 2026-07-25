{
  lib,
  python3Packages,
  writeText,
}:
python3Packages.buildPythonApplication {
  pname = "mcp-searxng-search";
  version = "1.0.0";
  pyproject = false;

  src = writeText "server.py" (builtins.readFile ./server.py);

  dontUnpack = true;

  propagatedBuildInputs = with python3Packages; [
    mcp
    httpx
    starlette
    uvicorn
  ];

  installPhase = ''
    mkdir -p $out/bin
    cp $src $out/bin/mcp-searxng-search
    chmod +x $out/bin/mcp-searxng-search
    wrapProgram $out/bin/mcp-searxng-search \
      --prefix PATH : ${lib.makeBinPath [python3Packages.python]} \
      --set PYTHONPATH ${python3Packages.python.withPackages (ps: with ps; [mcp httpx starlette uvicorn])}/${python3Packages.python.sitePackages}
  '';

  meta = {
    description = "SearXNG MCP server for web search";
    license = lib.licenses.mit;
    mainProgram = "mcp-searxng-search";
  };
}
