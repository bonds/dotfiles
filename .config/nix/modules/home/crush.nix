# Crush (charmbracelet/crush) — global config file.
#
# accismus-only: this module is imported solely by the accismus home-manager
# block (hosts/accismus/configuration.nix), so it needs no `enable` option —
# the same shape as pi.nix and polyptych.nix.
#
# Crush 0.99 loads a Bash `crushrc` from ~/.config/crush/crushrc (the older
# crush.json still works and merges with it; a project-local .crushrc /
# crush.json takes precedence over this global file).
#
# force = true is deliberate: Crush writes a crushrc of its own on first run
# (its built-in config skill does exactly that), so without force an unmanaged
# file at this path would make home-manager refuse to clobber it at activation.
# With force the store symlink always wins and activation is idempotent whether
# or not Crush ran first.
#
# Consequence of managing it here: ~/.config/crush/crushrc becomes a read-only
# store symlink, so Crush can no longer rewrite it — edit this repo and re-run
# `nr`. Per-project overrides still work via a project-local .crushrc.
_: {
  home.file.".config/crush/crushrc" = {
    source = ./crush/crushrc;
    force = true;
  };
}
