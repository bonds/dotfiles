{
  config,
  pkgs,
  lib,
  ...
}: let
  # osaurus ships a NOTARIZED bundle (spctl: Developer ID Terence Pae), so its
  # custom icon cannot be baked into the derivation the way the Zen overlay's is
  # — rewriting Contents invalidates the code signature and Gatekeeper then
  # rejects the app. Apply the icon to the Home Manager copy instead, after
  # copyApps has staged it. A FinderInfo xattr does not affect the signature.
  osaurusIcon = ../overlays/osaurus/osaurus-icon.icns;
  zenIcon = ../zen-icon.icns;
  appDir = "${config.home.homeDirectory}/Applications/Home Manager Apps";
  setOsaurusIconScript = pkgs.writeText "set-osaurus-icon.applescript" ''
    use framework "Cocoa"
    set appPath to "${appDir}/osaurus.app"
    set iconPath to "${osaurusIcon}"
    set img to (current application's NSImage's alloc()'s initWithContentsOfFile:iconPath)
    current application's NSWorkspace's sharedWorkspace()'s setIcon:img forFile:appPath options:2
  '';
  # Zen's icon is baked into the bundle by the overlay (Contents/Resources/
  # firefox.icns), which is necessary for the .app to be self-contained — but
  # macOS may still prefer the bundle's own Assets.car for display. Applying the
  # icon via NSWorkspace setIcon:options:2 writes the FinderInfo xattr, a
  # stronger display override that is independent of the bundle, and is what the
  # owner's original setup used. The xattr does not affect the code signature.
  setZenIconScript = pkgs.writeText "set-zen-icon.applescript" ''
    use framework "Cocoa"
    set appPath to "${appDir}/Zen.app"
    set iconPath to "${zenIcon}"
    set img to (current application's NSImage's alloc()'s initWithContentsOfFile:iconPath)
    current application's NSWorkspace's sharedWorkspace()'s setIcon:img forFile:appPath options:2
  '';
in {
  # macOS GUI .app bundles for accismus.
  #
  # These are home.packages (NOT environment.systemPackages): Home Manager copies
  # them to ~/Applications/Home Manager Apps — a stable, user-owned,
  # Spotlight-indexed path — instead of nix-darwin's system stager copying them
  # to /Applications/Nix Apps and re-registering stale /nix/store paths with
  # LaunchServices on every activation (see AGENTS.md §B). zen-browser's custom
  # icon and enterprise policies are baked into its bundle by the
  # modules/overlays/zen-browser overlay, and its icon is additionally applied to
  # the Home Manager copy via the zenIcon activation below (FinderInfo xattr).
  # daisydisk, ghosttile and openfang-desktop carry no custom icon.
  home.packages = with pkgs; [
    daisydisk # disk usage visualizer
    (pkgs.callPackage ../../pkgs/ghosttile {}) # hide apps from Dock/Cmd+Tab (local package)
    osaurus # native macOS AI agent harness (binary overlay, nr --update)
    openfang-desktop # OpenFang desktop app (Tauri binary overlay, nr --update)
    zen-browser # firefox fork with vertical tabs (binary overlay, nr --update)
    # Raven: native window for the `raven web` page (Swift wrapper built here,
    # see pkgs/raven-desktop). Icon is baked in — the bundle is ad-hoc signed
    # (nothing notarized to invalidate), so no activation step is needed.
    raven-desktop
  ];

  home.activation.osaurusIcon = lib.hm.dag.entryAfter ["copyApps"] ''
    if [ -d "${appDir}/osaurus.app" ]; then
      run /usr/bin/osascript "${setOsaurusIconScript}" || true
    fi
  '';

  home.activation.zenIcon = lib.hm.dag.entryAfter ["copyApps"] ''
    if [ -d "${appDir}/Zen.app" ]; then
      run /usr/bin/osascript "${setZenIconScript}" || true
    fi
  '';
}
