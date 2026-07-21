{
  lib,
  python3,
  transcribe-cpp,
  transcribe-cpp-python,
}:
python3.pkgs.buildPythonApplication {
  pname = "reel-summarize";
  version = "0.1.0";
  src = ./.;
  format = "pyproject";
  nativeBuildInputs = with python3.pkgs; [setuptools wrapPython];
  propagatedBuildInputs = with python3.pkgs; [httpx numpy] ++ [transcribe-cpp-python];
  nativeCheckInputs = with python3.pkgs; [pytest];
  preCheck = "export HOME=$(mktemp -d)";
  dontUsePythonRuntimeDepsCheck = true;
  makeWrapperArgs = [
    "--set"
    "TRANSCRIBE_LIBRARY"
    "${transcribe-cpp}/lib/libtranscribe.dylib"
  ];
  meta = with lib; {
    description = "Summarize Instagram Reels using local models (llama.cpp + transcribe.cpp, or Ollama)";
    homepage = "https://github.com/bonds/dotfiles";
    license = licenses.mit;
    platforms = platforms.all;
    maintainers = [];
  };
}
