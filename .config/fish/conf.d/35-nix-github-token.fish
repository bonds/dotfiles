# GitHub token for Nix source fetchers (flake inputs / tarballs).
#
# `nr --update` fires a burst of GitHub requests in one go: the overlay update
# scripts download release assets, then `nix flake update` re-resolves every
# input. Branch-style inputs (github:NousResearch/hermes-agent, agenix,
# flake-parts, ...) need an api.github.com call, and unauthenticated that limit
# is 60 requests/hour per IP — a shared/NAT'd IP trips it easily and the update
# dies with HTTP 429 midway:
#
#     2026-09-13: "rate-limited ... from your network" while fetching
#     hermes-agent, after the overlay bumps had already been applied.
#
# nix.conf is a plain key=value parser with no command substitution, so the
# token cannot be computed there — `access-tokens = github.com=$(gh auth token)`
# is stored (and sent) literally, and whitespace-split on top of that. It is
# exported here instead.
#
# NIX_CONFIG is *appended* to ~/.config/nix/nix.conf, not substituted for it, so
# the extra-trusted-substituters set there are preserved (losing those silently
# forces from-source builds — see the comment in that file).
#
# No secret is stored in this file, so it is safe to track in dotfiles.
# If `gh` is missing or logged out the value degrades to an empty token, which
# Nix treats as "no token", i.e. the previous unauthenticated behaviour.
# Cost: one `gh auth token` (login-keychain read, ~200ms) per shell start.
set -gx NIX_CONFIG "access-tokens = github.com="(gh auth token 2>/dev/null)
