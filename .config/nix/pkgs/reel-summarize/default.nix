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
  propagatedBuildInputs = with python3.pkgs; [httpx whisper];
  doCheck = false;
  meta = with lib; {
    description = "Summarize Instagram Reels using local models (Ollama + faster-whisper)";
    homepage = "https://github.com/bonds/dotfiles";
    license = licenses.mit;
    platforms = platforms.all;
    maintainers = [];
  };
}
