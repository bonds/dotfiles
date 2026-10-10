{
  config,
  pkgs,
  lib,
  ...
}: let
  # osaurus ships a NOTARIZED bundle (spctl: Developer ID Terence Pae), so its
  # custom icon cannot be baked into the derivation — rewriting Contents
  # invalidates the code signature and Gatekeeper then rejects the app. Apply
  # the icon to the Home Manager copy instead, after copyApps has staged it. A
  # FinderInfo xattr does not affect the signature.
  osaurusIcon = ../overlays/osaurus/osaurus-icon.icns;
  zenIcon = ../zen-icon.icns;
  zenPolicies = import ./zen-policies.nix;
  appDir = "${config.home.homeDirectory}/Applications/Home Manager Apps";
  setOsaurusIconScript = pkgs.writeText "set-osaurus-icon.applescript" ''
    use framework "Cocoa"
    set appPath to "${appDir}/osaurus.app"
    set iconPath to "${osaurusIcon}"
    set img to (current application's NSImage's alloc()'s initWithContentsOfFile:iconPath)
    current application's NSWorkspace's sharedWorkspace()'s setIcon:img forFile:appPath options:2
  '';
  # Zen's bundle is left as a pristine `undmg` extraction (Mozilla's Developer
  # ID signature intact), so the icon is NOT baked into it — baking would break
  # the seal. Applying the icon via NSWorkspace setIcon:options:2 writes the
  # FinderInfo xattr, which is independent of the bundle and does not affect the
  # code signature. This xattr is now the ONLY custom-icon mechanism.
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
  # LaunchServices on every activation (see AGENTS.md §B). Zen's custom icon is
  # applied to the Home Manager copy via the zenIcon activation below (FinderInfo
  # xattr); its enterprise policies come from macOS managed preferences set in
  # targets.darwin.defaults. Neither touches the bundle. daisydisk, ghosttile and
  # openfang-desktop carry no custom icon.
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

  # Zen enterprise policies via macOS managed preferences. The supported
  # mechanism is `defaults write app.zen-browser.zen <Key> <value>` (Zen issue
  # #12363: writing the .plist directly does NOT invalidate macOS's preferences
  # cache). home-manager's targets.darwin.defaults writer generates
  # `defaults import <domain> <plist>` from these attrs, which goes through the
  # `defaults` CLI and flushes the cache. `EnterprisePoliciesEnabled = true` is
  # the Firefox-family gate that makes Zen read this domain at all. The policy
  # set itself lives in the shared zen-policies.nix (also consumed by the Linux
  # wrapFirefox branch) — do NOT use programs.firefox here: its profile
  # management would risk taking over the owner's hand-built 2.1 GB profile
  # (AGENTS.md §B.1, "the profile trap").
  targets.darwin.defaults."app.zen-browser.zen" =
    {EnterprisePoliciesEnabled = true;}
    // zenPolicies;

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

  # Secretive (Secure Enclave SSH agent) — deliberately NOT in home.packages.
  # Upstream refuses to run unless its bundle physically lives in /Applications:
  # it rejects ~/Applications/Home Manager Apps (where copyApps stages apps) and
  # the /nix/store path those copies resolve from (upstream #810), because its
  # SecretAgent login-item helper fails to start anywhere else (#77). So a real
  # copy is materialised at /Applications/Secretive.app on every activation.
  # Keeping it in home.packages would leave a second, launchable copy for
  # Spotlight or `open -a Secretive` to pick by mistake. nixpkgs repacks the
  # official notarized release zip verbatim, so the bundle is byte-identical
  # (same Developer ID signature / designated requirement): existing Secure
  # Enclave keys, the com.maxgoedjen.Secretive.Host sandbox container and the
  # socket.ssh agent path in ~/.config/ssh/config are all unaffected. Version
  # bumps arrive via `nix flake update` (nr --update), not the in-app updater.
  home.activation.secretiveApplications = lib.hm.dag.entryAfter ["writeBoundary"] ''
    secretiveStoreApp="${pkgs.secretive}/Applications/Secretive.app"
    secretiveApp="/Applications/Secretive.app"
    if [ -d "$secretiveStoreApp" ]; then
      # The previous copy carries the store's read-only 0555 mode (ditto
      # preserves it), so rm cannot unlink inside it — it fails with
      # "Permission denied" and leaves "Directory not empty". Under the
      # activation's `set -e` that aborted the whole switch, which is why
      # `nr --update` reported "nh switch failed" and skipped its commit.
      # Restore owner-write first, and keep both steps non-fatal so a TCC
      # (App Management) denial cannot abort activation again.
      if [ -e "$secretiveApp" ]; then
        run /bin/chmod -R u+w "$secretiveApp" || true
        run /bin/rm -rf "$secretiveApp" || true
      fi
      # ditto (not cp -R) preserves the bundle's code signature, and the store
      # bundle contains no symlinks, so the copy has no references back into
      # /nix/store. A failure here is non-fatal on purpose: it means macOS
      # denied the write (App Management), and aborting would skip the rest of
      # home-manager's activation.
      if run /usr/bin/ditto "$secretiveStoreApp" "$secretiveApp"; then
        run /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$secretiveApp" || true
      else
        echo "secretive: could not copy $secretiveStoreApp to $secretiveApp" >&2
        echo "secretive: grant App Management to your terminal (System Settings > Privacy & Security > App Management) and re-run, or fix by hand:" >&2
        echo "secretive:   /bin/rm -rf $secretiveApp && /usr/bin/ditto $secretiveStoreApp $secretiveApp" >&2
      fi
    fi
  '';
}
