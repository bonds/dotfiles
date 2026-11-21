# OMP (`oh-my-pi`, omp.sh) — can1357's fork of pi, wired to the same Deep Infra
# provider and DeepSeek default as pi itself.
#
# accismus-only: imported solely by the accismus home-manager block
# (hosts/accismus/configuration.nix), so it needs no `enable` option — same
# shape as pi.nix and polyptych.nix.
#
# Deliberately NOT upstream's `homeManagerModules.default`: that module is the
# only thing their flake would give us, and the input would drag in crane,
# bun2nix, rust-overlay and a second nixpkgs for a package we do not build
# (pkgs/omp takes the prebuilt release binary instead — see its header). What
# the module does do, and what is reproduced below, is write `config.yml` as a
# WRITABLE REGULAR FILE rather than a store symlink: OMP takes an advisory lock
# on it and rewrites it at runtime (`/settings`, the model picker's role
# assignments, onboarding), and on macOS the lock backend creates an flock
# sidecar next to the file — both fail with EACCES against a read-only
# /nix/store symlink and break every launch.
#
# What OMP reads, and where it comes from:
#
#   ~/.omp/agent/models.yml   generated here from lib/deepinfra-models.nix —
#                             the SAME attrset pi's models.json uses, so models,
#                             list prices and the API-key command cannot drift
#   ~/.omp/agent/config.yml   generated here, copied into place at activation
#   ~/.agents/skills          already linked by pi.nix, and OMP's default
#                             `agents` provider reads it (enableAgentsUser is
#                             true by default) — no skills setting needed
#   ~/AGENTS.md, ~/DECISIONS.md  read directly (no config)
#
# `nr` is the only way to change any of it — same rule as pi.
{
  config,
  lib,
  pkgs,
  ...
}: let
  omp = pkgs.callPackage ../../pkgs/omp {};

  # Single source of truth for the provider block, shared with pi.nix.
  deepinfra = import ../../lib/deepinfra-models.nix;

  # `~/.omp/agent/models.yml` — YAML, same field names as pi's JSON. A
  # read-only symlink is safe here (unlike config.yml): the model registry only
  # READS this file, and the "legacy models.json is migrated to models.yml"
  # path in the docs only fires when neither YAML file exists — which never
  # happens while this symlink is in place. If a future release starts writing
  # it, the write fails loudly with EROFS and this should become an activation
  # copy like config.yml below.
  modelsFile = (pkgs.formats.yaml {}).generate "omp-models.yml" {
    providers.deepinfra = deepinfra;
  };

  # `~/.omp/agent/config.yml`. Model selection in OMP lives in `modelRoles`,
  # not in a defaultModel key: `default` is the chat model, and `smol`/`slow`/
  # `plan` are assigned explicitly because an unset role resolves against
  # OMP's built-in provider priorities (anthropic/openai/…), which have no
  # credentials here — a slash-less model id would then fail at the first
  # subagent or plan-mode turn.
  #
  #   default    the same model pi defaults to
  #   smol       the cheapest output rate of the five ($0.25/M), 1M context
  #   slow       default at explicit high effort (advisor/`--slow` turns)
  #   plan       default, since plan mode is the same model in pi
  #   enabledModels  the five Deep Infra models, enumerated rather than
  #                  `deepinfra/**`: OMP ships its own catalog slice for that
  #                  provider (dozens of models, including $25/M Claude rows
  #                  proxied by Deep Infra), so a glob would put far more than
  #                  our block in the picker. pi needs no such care — its
  #                  models.json only ever contains these five.
  #   startup.checkUpdate  off: the binary is pinned by nix, so a self-update
  #                  check can only nag. (Skills need no setting: OMP's default
  #                  `agents` provider reads `~/.agents/skills`, the Agent
  #                  Skills standard location pi.nix already links every skill
  #                  into — verified, all 9 load. `autolearn` is off by default
  #                  too, so OMP never writes skills of its own into
  #                  ~/.omp/agent/managed-skills.)
  settings = {
    modelRoles = {
      default = "deepinfra/deepseek-ai/DeepSeek-V4.1-Flash-1017";
      smol = "deepinfra/zai-org/GLM-5.3-Flash";
      slow = "deepinfra/deepseek-ai/DeepSeek-V4.1-Flash-1017:high";
      plan = "deepinfra/deepseek-ai/DeepSeek-V4.1-Flash-1017";
    };
    defaultThinkingLevel = "high";
    enabledModels = map (m: "deepinfra/${m.id}") deepinfra.models;
    startup.checkUpdate = false;
  };

  settingsFile = (pkgs.formats.yaml {}).generate "omp-config.yml" settings;
in {
  home.packages = [omp];

  home.file.".omp/agent/models.yml".source = modelsFile;

  # Same shape as the pi settings merge: run at activation, idempotent, and
  # never abort the switch. `install` replaces the file wholesale, so anything
  # OMP persisted into config.yml at runtime (a role picked in /models, a
  # /settings change) is overwritten by the declared values on the next `nr` —
  # intended: this file is the declaration, edits belong in the repo.
  home.activation.ompConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ompConfig="${config.home.homeDirectory}/.omp/agent/config.yml"
    run mkdir -p "$(dirname "$ompConfig")"
    run install -m 600 ${settingsFile} "$ompConfig"
  '';
}
