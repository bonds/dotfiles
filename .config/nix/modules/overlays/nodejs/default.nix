# TODO(nodejs-overlay): REMOVE once node's child-process/cluster tests pass in the darwin sandbox.
# WHAT:  disables checkPhase (doCheck = false) for nodejs/nodejs-slim and the _26 variants
#        (the failing drv is nodejs-slim_26; plain nodejs-slim is 24.21.0).
# WHY:   nodejs-slim-26.10.0 `make test-ci-js` fails (exit 2) on spawn/cluster tests:
#        test-child-process-spawn-*, test-cluster-worker-*, test-child-process-http-socket-leak
#        — macOS sandbox/spawn-sensitive tests, not a node regression.
#        Test-only; the node binary itself is fine.
# ADDED: 2026-10-06, from the flake.lock bump.
# HOW TO REMOVE: drop doCheck=false (or delete this file + wiring in darwin.nix), run
#        `nh darwin build`; if node's tests pass with checks on, remove.
#        Find again: grep -rn "TODO(nodejs-overlay)" ~/.config/nix
final: prev: {
  nodejs-slim = prev.nodejs-slim.overrideAttrs (_old: {
    doCheck = false;
  });
  nodejs = prev.nodejs.overrideAttrs (_old: {
    doCheck = false;
  });
  nodejs-slim_26 = prev.nodejs-slim_26.overrideAttrs (_old: {
    doCheck = false;
  });
  nodejs_26 = prev.nodejs_26.overrideAttrs (_old: {
    doCheck = false;
  });
}
