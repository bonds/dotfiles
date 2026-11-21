# pi (earendil-works/pi) — Deep Infra provider + DeepSeek-V4.1-Flash-1017 default,
# plus the shared agent skills that every harness on this machine reads.
#
# accismus-only: this module is imported solely by the accismus home-manager
# block (hosts/accismus/configuration.nix), so it needs no `enable` option —
# same shape as polyptych.nix.
#
# The API key is NOT stored here. pi's config has no keychain/agenix binding,
# but its `apiKey` accepts a leading `!command` which it runs at request time;
# models.json therefore carries only a command that reads the key out of the
# agenix-decrypted env file — the SAME secret hermes-agent uses
# (secrets/hermes-deepinfra.age → /run/agenix/hermes-deepinfra, declared in
# hosts/accismus/configuration.nix, mode 0400 owner scott). Only the reference
# is tracked; the literal key never enters the (public) repo.
#
# Everything pi READS is a read-only home.file symlink into this repo, so the
# setup is reproducible on any machine and reviewable in git:
#
#   agent-skills/         shared with every agent (see skillLinks below)
#   lib/deepinfra-models.nix  the provider block, also used by OMP (omp.nix)
#   pkgs/pi/extensions/   safety + UX extensions
#   pkgs/pi/prompts/      /review, /ship, /nr, /learn
#   pkgs/pi/keybindings.json
#   (mcp.json is generated below)
#
# settings.json and fast-tui.json are MERGED rather than symlinked, because both
# are written at runtime. Consequence of the symlinks: `pi mcp add` cannot
# persist (mcp.json is regenerated on every activation), and `pi install` writes
# into settings.json — which does survive `nr`, but only on this machine. That is
# why packages are declared in the merge below: a fresh checkout would otherwise
# get none of them.
{
  config,
  lib,
  pkgs,
  ...
}: let
  piConfig = ../../pkgs/pi;

  # The Deep Infra provider block: models, list prices and the API-key command,
  # shared with OMP (modules/home/omp.nix) so the two agents cannot drift.
  deepinfra = import ../../lib/deepinfra-models.nix;

  # Canonical, tracked agent skills (Agent Skills format: <name>/SKILL.md).
  # They live in .config/nix/agent-skills, not pkgs/pi, because every harness
  # reads them, not just pi.
  #
  # Each agent gets one symlink PER SKILL rather than a symlink of the whole
  # directory: opencode and Hermes already own skills in their directories,
  # and keeping those directories real means the agents can still add their
  # own. `builtins.readDir` picks up new skills on the next rebuild, so adding
  # a skill is just a new directory under .config/nix/agent-skills.
  #
  #   ~/.agents/skills            Agent Skills standard location — pi reads
  #                               this too, so it is the ONLY pi path: linking
  #                               both makes every skill collide at startup
  #   ~/.claude/skills            Claude Code personal skills
  #   ~/.config/opencode/skills   opencode
  #   ~/.hermes/skills/dotfiles   Hermes (global; skills live in a category dir)
  agentSkills = ../../agent-skills;
  skillNames = builtins.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir agentSkills)
  );
  skillLinks = dir:
    lib.listToAttrs (map (name: {
        name = "${dir}/${name}";
        value.source = agentSkills + "/${name}";
      })
      skillNames);
in {
  home.file =
    (skillLinks ".agents/skills")
    // (skillLinks ".claude/skills")
    // (skillLinks ".config/opencode/skills")
    // (skillLinks ".hermes/skills/dotfiles")
    // {
      # Hermes groups skills by category and shows the category description in
      # its prompt. Symlinked skills show up as source=local, enabled. The
      # curator/update machinery only touches hub-installed skills, so these
      # stay untouched.
      ".hermes/skills/dotfiles/DESCRIPTION.md".text = ''
        Scott's dotfiles, machines and services: layout of the tracked config,
        per-machine setup (accismus, sophrosyne, metanoia), the firesafe backup
        and photos pipeline, the GitHub token split, the osaurus build lane,
        and the code-review workflow.

        Hermes does not read AGENTS.md: the rules for this machine live in
        ~/AGENTS.md — read it before changing anything. Memory is `mem` (see the
        memory skill): `mem recall "<words>"` before re-deriving an answer, and
        `mem inbox add` to capture a lesson.
      '';

      # pi only READS models.json (its writable, auto-refreshed catalog is
      # models-store.json), so a read-only home.file symlink is safe here. The
      # provider block — including why the cost numbers are Deep Infra's LIST
      # prices and what `reported-cost.ts` does about the discount — lives in
      # lib/deepinfra-models.nix, because OMP needs the same one.
      ".pi/agent/models.json".text = builtins.toJSON {
        providers.deepinfra = deepinfra;
      };

      # pi's own resources: read-only, discovered by convention (no settings
      # arrays needed). Skills are symlinked per skill above, since they are
      # shared with the other agents.
      ".pi/agent/extensions".source = piConfig + "/extensions";
      ".pi/agent/prompts".source = piConfig + "/prompts";
      ".pi/agent/keybindings.json".source = piConfig + "/keybindings.json";

      # Settled decisions and their rationale: AGENTS.md says what to do, this
      # says why, so an odd-looking choice is not re-litigated every session.
      # At $HOME root (not under .pi) so every harness can find it.
      "DECISIONS.md".source = piConfig + "/decisions.md";

      # MCP servers. reel-summarize-mcp runs on sophrosyne and speaks streamable
      # HTTP; the `/sse` path is only a path name (pi rejects the legacy SSE
      # transport, not this URL). Reachable over Tailscale only. The bearer
      # token is optional on the server side; set REEL_SUMMARIZE_MCP_TOKEN here
      # if it is ever enabled there.
      ".pi/agent/mcp.json".text = builtins.toJSON {
        mcpServers.reel-summarize = {
          url = "http://sophrosyne.taileafac.ts.net:8892/sse";
          description = "Summarize Instagram Reels: transcript, sampled frames, vision OCR, final summary.";
        };
      };
    };

  # settings.json is the opposite case: pi WRITES it at runtime (it bumped
  # `lastChangelogVersion` on first launch), so a read-only home.file symlink
  # would clobber pi's own writes. Merge our keys in with jq instead —
  # the same preserve-all-other-keys pattern used for Raven's config.json in
  # hosts/accismus/configuration.nix postActivation. Idempotent, so a re-run
  # never aborts activation under `set -e`.
  #
  #   enabledModels   all Deep Infra models are in the Ctrl+P cycle (with a
  #                   single model the cycle is a no-op). `**`, not `*`: model
  #                   IDs contain a slash (`deepseek-ai/…`) and the glob does
  #                   not cross it — `deepinfra/*` matches nothing and pi warns.
  #   defaultTools    `+codemode` adds the codemode tool next to the built-in
  #                   defaults: the model can call tools from a script instead
  #                   of one round-trip each.
  #   packages        third-party UI, declared here so a fresh machine gets
  #                   them: pi-fast-tui (header, footer, editor frame, turn
  #                   telemetry) and pi-tidy-tools (two-line, reason-first tool
  #                   rows). Both are cosmetic — nothing here depends on them.
  #                   pi-tidy-tools defaults to ENABLED when
  #                   ~/.pi/agent/pi-tidy-tools.json is absent, so it needs no
  #                   seeded state; only fast-tui's toolView needs pinning (see
  #                   piFastTuiSettings below).
  home.activation.piSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    piSettings="${config.home.homeDirectory}/.pi/agent/settings.json"
    mkdir -p "$(dirname "$piSettings")"
    if [ ! -f "$piSettings" ]; then
      echo '{}' > "$piSettings"
    fi
    piTmp="$(mktemp "$piSettings.XXXXXX")"
    if ${pkgs.jq}/bin/jq \
      '."$schema" = "https://pi.dev/schemas/settings.schema.json"
       | .defaultProvider = "deepinfra"
       | .defaultModel = "deepseek-ai/DeepSeek-V4.1-Flash-1017"
       | .defaultThinkingLevel = "high"
       | .enabledModels = ["deepinfra/**"]
       | .defaultTools = ["+codemode"]
       | .theme = "system"
       | .quietStartup = "header"
       | .enableInstallTelemetry = false
       | .packages = ["npm:pi-fast-tui", "npm:@mobrienv/pi-tidy-tools"]' "$piSettings" > "$piTmp"; then
      mv "$piTmp" "$piSettings"
    else
      rm -f "$piTmp"
      echo "warning: pi settings.json merge failed; left unchanged" >&2
    fi
  '';

  # fast-tui defaults `toolView.mode` to "cards", and pi's
  # `registerToolRenderer` resolvers run ABOVE a tool's own renderer — so its
  # cards hide every pi-tidy row no matter which extension loads first. Pinning
  # "native" makes fast-tui defer to the registered tool, which is pi-tidy's:
  # fast-tui keeps the chrome (header, footer, editor frame, telemetry),
  # pi-tidy owns the tool rows. fast-tui writes this file from its `/fast-tui`
  # menu, so merge it the same way as settings.json rather than symlinking.
  home.activation.piFastTuiSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    fastTui="${config.home.homeDirectory}/.pi/agent/fast-tui.json"
    mkdir -p "$(dirname "$fastTui")"
    if [ ! -f "$fastTui" ]; then
      echo '{}' > "$fastTui"
    fi
    fastTuiTmp="$(mktemp "$fastTui.XXXXXX")"
    if ${pkgs.jq}/bin/jq '.toolView.mode = "native"' "$fastTui" > "$fastTuiTmp"; then
      mv "$fastTuiTmp" "$fastTui"
    else
      rm -f "$fastTuiTmp"
      echo "warning: fast-tui settings merge failed; left unchanged" >&2
    fi
  '';
}
