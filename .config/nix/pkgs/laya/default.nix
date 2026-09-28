{
  lib,
  buildPythonPackage,
  fetchPypi,
  python3,
  torchWithoutCuda,
}: let
  # convaiinnovations/laya 0.3.20 — System-1 decision engine used as the
  # reel-summarize line-salience pre-filter.  Depends on torch + transformers +
  # ModernBERT.  doCheck=false: upstream's test suite needs network/GPU and
  # would need a full model load; we gate the actual model against the
  # checkpoint FOD at runtime via LAYA_CHECKPOINT_DIR.
  pname = "laya";
  version = "0.3.20";
in
  buildPythonPackage {
    inherit pname version;
    src = fetchPypi {
      inherit pname version;
      hash = "sha256-aS3hNGzwI5u3u8/98M+9U4wkg0+Lxh6bYPQQZGXAM8k=";
    };
    pyproject = true;
    python = python3;

    # torchWithoutCuda (CPU-only prebuilt wheel) instead of source torch —
    # avoids the multi-hour compilation and drops CUDA/NCCL entirely (no GPU
    # on sophrosyne).  x86_64-linux only (built on sophrosyne).
    propagatedBuildInputs = [
      torchWithoutCuda
      python3.pkgs.transformers
      python3.pkgs.safetensors
      python3.pkgs.huggingface-hub
      python3.pkgs.numpy
    ];

    doCheck = false;
    pythonImportsCheck = ["laya" "laya.router"];

    meta = with lib; {
      description = "Fast, non-autoregressive System 1 decision engine with calibrated probabilities (ModernBERT)";
      homepage = "https://huggingface.co/convaiinnovations/laya";
      license = licenses.asl20;
      platforms = platforms.linux; # torchWithoutCuda is linux/x86_64
      maintainers = [];
    };
  }
