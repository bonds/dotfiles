{
  lib,
  python3,
}:
python3.pkgs.buildPythonApplication {
  pname = "reel-summarize";
  version = "0.1.0";
  src = ./.;
  format = "pyproject";
  nativeBuildInputs = with python3.pkgs; [setuptools];
  propagatedBuildInputs = with python3.pkgs; [httpx openai-whisper];
  nativeCheckInputs = with python3.pkgs; [pytest];
  preCheck = "export HOME=$(mktemp -d)";
  dontUsePythonRuntimeDepsCheck = true;
  meta = with lib; {
    description = "Summarize Instagram Reels using local models (Ollama + whisper)";
    homepage = "https://github.com/bonds/dotfiles";
    license = licenses.mit;
    platforms = platforms.all;
    maintainers = [];
  };
}
