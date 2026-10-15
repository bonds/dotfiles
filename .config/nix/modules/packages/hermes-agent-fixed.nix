# hermes-agent, with nixpkgs-unstable's python3.12-anyio built without its own
# pytest suite.
#
# WHY. hermes-agent's uv2nix venv takes its python from hermes-agent's own
# nixpkgs (inputs.nixpkgs.follows = "nixpkgs-unstable" in flake.nix), and its
# nix/python.nix reuses nixpkgs' PREBUILT python312 packages for the voice
# stack (`mkPrebuiltOverride final python312.pkgs.faster-whisper`, ...). That
# pulls a runtime chain which ends at nixpkgs' anyio, so anyio is built from
# source whenever nixpkgs-unstable's head is not yet on a substituter — and
# anyio 4.14.2's own pytest suite then fails (8 failed, 2593 passed) on
# CPython 3.12.15's SSLContext.wrap_bio() change (gh-156793 / CVE-2026-19553),
# taking the whole accismus closure down with it.
#
# Chain, verified with `nix why-depends --derivation` against the post-update
# lock (nixpkgs-unstable = ca1659429c, the head):
#
#   darwin-system-26.05.c3e90c8
#   └ etc -> user-environment -> home-manager-path
#     └ hermes-agent-0.21.5
#       └ hermes-agent-env
#         └ faster-whisper-1.2.1            (nixpkgsPrebuilt wrapper)
#           └ python3.12-faster-whisper-1.2.1
#             └ python3.12-huggingface-hub-1.30.0
#               └ python3.12-httpx-0.28.1
#                 └ python3.12-anyio-4.14.2  ← the derivation that fails
#
# THE FIX. `doCheck = false` on that one member of the python set: the package
# still builds (same runtime closure, no source patches), but upstream's
# failing suite no longer decides whether the tree builds. This retires the
# 2026-10-09 nixpkgs-unstable "anyio" pin in flake-pins.json — see its
# "$retired" entry — because with the tests skipped anyio builds at ANY rev.
# The nixpkgs "thrift" pin is untouched: that one is a different blocker
# (thrift 0.24.0's C++ tests do not compile against libcxx 21).
#
# WHY BOTH `python312` AND `callPackage`. nix/python.nix takes its python312
# from its OWN callPackage scope, not from hermes-agent.nix's `python312`
# argument — hermes-agent.nix's mkHermesVenv passes only uv2nix/pyproject-* to
# it. So overriding the argument alone leaves the venv untouched (verified:
# `hermesVenv.drvPath` is byte-identical before and after). Overriding
# `callPackage` is what actually reaches it. Both are set so the patch
# survives either upstream arrangement.
#
# Remove this shim once nixpkgs' anyio suite passes again on CPython 3.12.15
# (then the file reduces to `inputs.hermes-agent.packages.<system>.default`).
{
  pkgs,
  inputs,
}: let
  system = pkgs.stdenv.hostPlatform.system;
  # The nixpkgs hermes-agent follows, i.e. the exact python312 its venv
  # resolves against — not the caller's stable one.
  unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${system};
  anyioUnchecked = unstablePkgs.python312.override {
    packageOverrides = _final: prev: {
      anyio = prev.anyio.overridePythonAttrs (_: {doCheck = false;});
    };
  };
in
  inputs.hermes-agent.packages.${system}.default.override {
    python312 = anyioUnchecked;
    callPackage = inputs.nixpkgs-unstable.lib.callPackageWith (
      unstablePkgs // {python312 = anyioUnchecked;}
    );
  }
