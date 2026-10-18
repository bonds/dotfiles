{
  config,
  lib,
  pkgs,
  ...
}: {
  home.stateVersion = "26.05";

  # Repair home-manager's own links right after each activation.
  #
  # HM re-links every managed path on each run, but it does not remove a
  # DIRECTORY symlink when a path changes from one whole-dir symlink to
  # per-file links. That leaves the path resolving into an old generation (and
  # dangling once it is collected) — it is how pi ended up seeing every skill
  # twice ("[Skill conflicts]"): ~/.pi/agent/skills stayed a symlink after the
  # switch to per-skill links. See bin/hm-links for the full story.
  #
  # Cheap (a few hundred stat calls), idempotent, and only ever repoints a
  # symlink at the current generation. `hm-links` (no args) audits; `--scan`
  # also hunts for orphan links the current generation no longer manages.
  home.activation.hmLinks = lib.hm.dag.entryAfter ["linkGeneration"] ''
    if [ -x "$HOME/bin/hm-links" ]; then
      # $newGenPath, not the current-home gcroot: home-manager re-points the
      # gcroot at the very END of activation (nix-store --add-root), so
      # reading it here would resolve to the PREVIOUS generation and the
      # "repair" would undo linkNewGen.
      ${pkgs.bash}/bin/bash "$HOME/bin/hm-links" --fix --quiet --generation "$newGenPath" || true
    fi
  '';

  imports = [
    ./ghostty.nix
    ./tmux.nix
    ./what-changed.nix
  ];

  programs.what-changed = {
    enable = true;
    settings = {
      backend = "openai";
      host = "http://sophrosyne.taileafac.ts.net:8080";
      model = "qwen2.5-7b";
      timeout = 240;
      maxInputBytes = 4000;
    };
  };
}
