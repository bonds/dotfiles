{pkgs, ...}: {
  # Orca (agent IDE, https://www.onorca.dev/) — stablyai/orca.
  #
  # Managed as a home.packages entry (NOT environment.systemPackages) so Home
  # Manager stages the bundled .app to ~/Applications/Home Manager Apps/Orca.app
  # — a stable, user-owned, Spotlight-indexed path. The darwin-system stager
  # (environment.systemPackages) instead copies .app bundles to
  # /Applications/Nix Apps and re-registers them with LaunchServices on every
  # activation, which left STALE store-path registrations (rejected bundles)
  # that made `open -a Orca`/Spotlight resolve to a "damaged" build even after
  # the derivation was fixed (see photo-export.nix for the same note).
  home.packages = [pkgs.orca-ade];
}
