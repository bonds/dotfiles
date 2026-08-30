{
  lib,
  python3,
  fetchFromGitHub,
  transcribe-cpp,
}:
python3.pkgs.buildPythonPackage {
  pname = "transcribe-cpp-python";
  version = "0.1.3";
  format = "pyproject";

  src = fetchFromGitHub {
    owner = "handy-computer";
    repo = "transcribe.cpp";
    rev = "v0.1.3";
    hash = "sha256-EnmekQEoJtSJXtc6YPtNP8mbA/KMg8qBoMekRvZKqrg=";
  };
  # The Python binding lives under bindings/python
  sourceRoot = "source/bindings/python";

  nativeBuildInputs = with python3.pkgs; [
    hatchling
  ];

  # The native library is loaded via TRANSCRIBE_LIBRARY env var at runtime.
  # We don't propagate it as a Python dep — instead, the consumer sets the
  # env var (e.g. via makeWrapperArgs in reel-summarize).
  # propagatedBuildInputs = [ transcribe-cpp ];

  dontCheckRuntimeDeps = true;

  # Skip import check — transcribe_cpp loads the native library at import time,
  # which isn't available during the build check. Runtime correctness is
  # verified by the reel-summarize preflight check.
  pythonImportsCheck = [];

  meta = with lib; {
    description = "Python bindings for transcribe.cpp (pure ctypes)";
    homepage = "https://github.com/handy-computer/transcribe.cpp";
    license = licenses.mit;
    maintainers = [];
  };
}
