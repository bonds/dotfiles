# TODO(mcp-overlay): REMOVE once python3.12-mcp/3.13-mcp tests pass unmodified in the nix sandbox.
# WHAT:  sets __darwinAllowLocalNetworking = true for mcp (allows pytestCheckPhase servers to bind localhost).
# WHY:   pytestCheckPhase failed with 24x `TimeoutError: Server on port … did not start within 20.0 seconds`
#        — classic macOS nix-sandbox localhost-binding restriction, not a test regression.
#        Test-only; package/library fine. (Keeps checks ON, unlike the anyio overlay's doCheck=false.)
# ADDED: 2026-10-05, after the flake.lock bump made python3.13-mcp-1.26.0 fail its check phase.
# HOW TO REMOVE: drop __darwinAllowLocalNetworking (or delete this file + wiring in darwin.nix), run
#        `nh darwin build`; if mcp passes with checks on normally, remove.
#        Find again: grep -rn "TODO(mcp-overlay)" ~/.config/nix
final: prev: {
  pythonPackagesExtensions =
    prev.pythonPackagesExtensions
    ++ [
      (_pfinal: pyprev: {
        mcp = pyprev.mcp.overridePythonAttrs (_old: {
          __darwinAllowLocalNetworking = true;
        });
      })
    ];
}
