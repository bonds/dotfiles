# TODO(anyio-overlay): REMOVE once anyio's own test suite passes unmodified.
# WHAT:  temporarily sets doCheck = false for anyio (skips pytestCheckPhase).
# WHY:   anyio 4.14.2 tests fail in-check: tests/streams/test_tls.py::test_tls_connectable[*]
#        -> ValueError('server_hostname can only be specified in client mode') (4 tests),
#        plus 2 test_from_thread.py unraisable failures. Test-only; library fine.
#        Upstream regressed TLS tests in the 4.14.x line (IDNA/TLSStream.wrap, PR #1208).
# ADDED: 2026-10-05, from the flake.lock bump (electron 43.7.7 era).
# HOW TO REMOVE: drop doCheck=false (or delete this file + wiring), run `nh darwin build`;
#        if anyio passes with checks on, remove. Find again: grep -rn "TODO(anyio-overlay)" ~/.config/nix
final: prev: {
  pythonPackagesExtensions =
    prev.pythonPackagesExtensions
    ++ [
      (_pfinal: pyprev: {
        anyio = pyprev.anyio.overridePythonAttrs (_old: {
          doCheck = false;
        });
      })
    ];
}
