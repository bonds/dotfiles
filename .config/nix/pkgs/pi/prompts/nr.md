---
description: Verify a nix change with a build, then hand the activation to Scott
argument-hint: "[host: accismus|sophrosyne|metanoia]"
---
Verify the nix change for ${1:-this host} **without activating it**.

Allowed (build-only):
- accismus: `nh darwin build` (no `switch`)
- sophrosyne / metanoia: `nix flake check` and a remote `nix build`, or
  `ssh sophrosyne "fish -c 'nh os build'"`

Never run the activating command yourself: no `nr`, no
`nixos-rebuild switch`, no `darwin-rebuild switch`, no `home-manager switch`.
Scott runs the switch, because activation is his to approve.

Report:
- what you built and the result
- any warnings from the build
- the exact command for Scott to run, e.g. `nr` (accismus) or
  `ssh sophrosyne "fish -c 'nr'"` (sophrosyne)

If the build itself fails, diagnose and fix it; do not fall back to activating.
