{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
}:
stdenv.mkDerivation rec {
  pname = "transcribe-cpp";
  version = "0.1.3";

  src = fetchFromGitHub {
    owner = "handy-computer";
    repo = "transcribe.cpp";
    rev = "v${version}";
    hash = "sha256-EnmekQEoJtSJXtc6YPtNP8mbA/KMg8qBoMekRvZKqrg=";
  };

  nativeBuildInputs = [
    cmake
    ninja
  ];

  cmakeFlags = [
    "-DTRANSCRIBE_BUILD_SHARED=ON"
    "-DTRANSCRIBE_BUILD_TESTS=OFF"
    "-DTRANSCRIBE_BUILD_EXAMPLES=OFF"
    "-DTRANSCRIBE_BUILD_TOOLS=OFF"
    "-DTRANSCRIBE_INSTALL=ON"
    "-DTRANSCRIBE_METAL=${
      if stdenv.hostPlatform.isDarwin
      then "ON"
      else "OFF"
    }"
    "-DTRANSCRIBE_VULKAN=OFF"
    "-DTRANSCRIBE_CUDA=OFF"
    "-DGGML_METAL_EMBED_LIBRARY=${
      if stdenv.hostPlatform.isDarwin
      then "ON"
      else "OFF"
    }"
    "-DTRANSCRIBE_USE_OPENMP=OFF"
    "-DTRANSCRIBE_USE_SYSTEM_BLAS=OFF"
  ];

  preConfigure = lib.optionalString stdenv.hostPlatform.isDarwin ''
    export MACOSX_DEPLOYMENT_TARGET=12.0
  '';

  meta = with lib; {
    description = "C/C++ speech-to-text inference library using ggml";
    homepage = "https://github.com/handy-computer/transcribe.cpp";
    license = licenses.mit;
    platforms = platforms.unix;
    maintainers = [];
  };
}
