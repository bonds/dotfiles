# TODO(lix-overlay): REMOVE once lix's functional2 test fits its 300s budget.
# WHAT:  disables lix's installCheckPhase (doInstallCheck = false).
# WHY:   test 80/80 `lix:functional2` TIMEOUT at 300.02s (SIGTERM); 0 real failures
#        (71 ok / 8 skipped / 1 timeout) — just a 300s test-budget overrun on this Mac.
#        (Supersedes the earlier mesonInstallCheckFlags --timeout-multiplier=0 attempt,
#        which still produced the timing-out drv.)
# ADDED: 2026-10-05, from the flake.lock bump (lix 2.95.2).
# HOW TO REMOVE: drop doInstallCheck=false (or delete this file + wiring in darwin.nix),
#        run `nh darwin build`; if lix's tests pass, remove.
#        Find again: grep -rn "TODO(lix-overlay)" ~/.config/nix
_final: prev: {
  lixPackageSets =
    prev.lixPackageSets
    // {
      latest =
        prev.lixPackageSets.latest
        // {
          lix = prev.lixPackageSets.latest.lix.overrideAttrs (_old: {
            doInstallCheck = false;
          });
        };
    };
}
