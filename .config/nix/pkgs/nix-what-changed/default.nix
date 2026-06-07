{
  lib,
  python3,
}:
python3.pkgs.buildPythonApplication {
  pname = "what-changed";
  version = "0.7.0";
  src = ./.;
  format = "pyproject";
  nativeBuildInputs = with python3.pkgs; [setuptools];
  propagatedBuildInputs = with python3.pkgs; [rich httpx];
  doCheck = false;
  meta = with lib; {
    description = "Show nix system package changelogs using LLM";
    homepage = "https://github.com/bonds/dotfiles";
    license = licenses.mit;
    platforms = platforms.all;
    maintainers = [];
  };
}
