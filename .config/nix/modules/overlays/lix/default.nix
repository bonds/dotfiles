# Prevent lix's installCheckPhase from timing out at the meson suite level.
#
# lix is pinned via `nix.package = pkgs.lixPackageSets.latest.lix` and is not
# prebuilt in any configured cache on darwin, so every rebuild compiles it from
# source. Its installCheckPhase runs the full upstream test suite (~80 groups
# via `meson test --no-rebuild --suite=installcheck`).
#
# The `check` suite gets meson's `--timeout-multiplier=0` from nixpkgs' meson
# setup-hook, but lix overrides installCheckPhase and does *not* pass it to the
# installcheck suite. Under heavy parallel load the slow `functional2` pytest
# group (worksteal across 12 workers) can exceed meson's per-test default
# timeout (300s) and get SIGTERM'd even though all subtests pass — aborting the
# whole rebuild.
#
# This keeps `doInstallCheck = true` and only disables the meson-level test
# timeout for the installcheck suite, so the tests still run. pytest-timeout
# inside the harness still catches genuinely-hung tests individually.
_final: prev: {
  lixPackageSets =
    prev.lixPackageSets
    // {
      latest =
        prev.lixPackageSets.latest
        // {
          lix = prev.lixPackageSets.latest.lix.overrideAttrs (old: {
            mesonInstallCheckFlags =
              (old.mesonInstallCheckFlags or ["--suite=installcheck" "--print-errorlogs"])
              ++ ["--timeout-multiplier=0"];
          });
        };
    };
}
