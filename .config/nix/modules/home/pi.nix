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
#   pkgs/pi/extensions/   safety + UX extensions
#   pkgs/pi/prompts/      /review, /ship, /nr, /learn
#   pkgs/pi/keybindings.json
#   (mcp.json is generated below)
#
# Only settings.json is merged instead of symlinked, because pi writes it at
# runtime. Consequence of the symlinks: `pi install` / `pi mcp add` cannot
# persist into these paths — edit the repo and re-run `nr` instead.
{
  config,
  lib,
  pkgs,
  ...
}: let
  piConfig = ../../pkgs/pi;

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
      '';

      # pi only READS models.json (its writable, auto-refreshed catalog is
      # models-store.json), so a read-only home.file symlink is safe here.
      ".pi/agent/models.json".text = builtins.toJSON {
        providers.deepinfra = {
          name = "Deep Infra";
          baseUrl = "https://api.deepinfra.com/v1/openai";
          api = "openai-completions";
          apiKey = "!/usr/bin/sed -n 's/^DEEPINFRA_API_KEY=//p' /run/agenix/hermes-deepinfra";
          models = [
            {
              id = "deepseek-ai/DeepSeek-V4.1-Flash-1017";
              # Plain label: `model-prices.ts` appends the billed prices, which
              # is what the built-in /model selector prints for the highlighted
              # model (`Model Name: <name>`) — its rows are `id` + `[provider]`
              # only, and an extension may not replace it (a command named
              # `model` is skipped in favour of the built-in). Billed rather than
              # list prices live there because the discount is per model, and
              # that is also why they are not written here: this file is static,
              # the discount is not.
              name = "DeepSeek V4.1 Flash 1017";
              api = "openai-completions";
              reasoning = true;
              input = ["text" "image"];
              contextWindow = 1048576;
              # Deep Infra reports `max_tokens` == `context_length` for this
              # model (metadata, `curl api.deepinfra.com/v1/openai/models`), so
              # this is the provider's own ceiling, not a typo. pi clamps it to
              # the room left in the context anyway.
              maxTokens = 1048576;
              compat.maxTokensField = "max_tokens";

              # USD per MILLION tokens — required for /session and the footer
              # to show a cost at all. Without this object pi reports every
              # request at $0: pi prices requests as `tokens x model.cost` and
              # never reads a cost field out of the provider response, and
              # `deepinfra` has no pi.dev catalog entry to supply prices.
              #
              # These are Deep Infra's LIST prices for this model
              # (`curl api.deepinfra.com/v1/openai/models` -> metadata.pricing):
              # input 0.2, output 0.6, cache_read 0.006. There is no cache_write
              # price (prompt caching is implicit, writes bill at the input
              # rate), and the OpenAI-compatible API only reports cached_tokens
              # (cacheRead), so cacheWrite tokens stay 0.
              #
              # They are NOT what we are billed: this model currently carries
              # `metadata.discount: 0.51`, so the effective rate is 0.49x of
              # list, and discounts expire without notice. The `reported-cost.ts`
              # extension (pkgs/pi/extensions/) rewrites each finished message's
              # usage.cost from Deep Infra's own per-request
              # `usage.estimated_cost`, rescaling these components
              # proportionally. So: keep list prices here as the
              # shape/fallback, let the extension supply the real number. If
              # Deep Infra stops reporting a cost, /session falls back to
              # roughly 2x the true cost until this object is updated.
              cost = {
                input = 0.2;
                output = 0.6;
                cacheRead = 0.006;
                cacheWrite = 0.2;
              };
            }

            # Cheap/fast partners for Ctrl+P cycling (`enabledModels` below).
            # All four are cheaper than the 1017 on input and all but Qwen3.8
            # Flash are vision-capable; prices are Deep Infra's list prices from
            # the same `metadata.pricing` response as the model above. Where
            # `metadata.discount` is set it is noted per model — list price is
            # kept here as the fallback shape, and `reported-cost.ts` supplies
            # the real per-request number.
            {
              # $0.20/$2.50 list, discount 0.25 (billed ~0.75x). 256k context,
              # not 1M — the tightest of the four. Dense 27B, so output is the
              # expensive side; good for short answers, not long generations.
              id = "Qwen/Qwen3.8-27B";
              name = "Qwen3.8 27B";
              api = "openai-completions";
              reasoning = true;
              input = ["text" "image"];
              contextWindow = 262144;
              maxTokens = 262144;
              compat.maxTokensField = "max_tokens";
              cost = {
                input = 0.2;
                output = 2.5;
                cacheRead = 0.05;
                cacheWrite = 0.2;
              };
            }
            {
              # $0.075/$0.25 list, no discount — the cheapest output rate in
              # the cycle by an order of magnitude, with the 1017's 1M context.
              id = "zai-org/GLM-5.3-Flash";
              name = "GLM-5.3 Flash";
              api = "openai-completions";
              reasoning = true;
              input = ["text" "image"];
              contextWindow = 1048576;
              maxTokens = 1048576;
              compat.maxTokensField = "max_tokens";
              cost = {
                input = 0.075;
                output = 0.25;
                cacheRead = 0.015;
                cacheWrite = 0.075;
              };
            }
            {
              # $0.113/$0.382 list, no discount. Text-only (its catalogue tags
              # are chat/prompt_cache/reasoning_effort — no `vision`, unlike the
              # 27B), 1M context at a flat rate across the whole window, and it
              # accepts a reasoning effort. Sits between GLM (cheaper) and MiMo
              # (pricier) on output.
              id = "Qwen/Qwen3.8-Flash";
              name = "Qwen3.8 Flash";
              api = "openai-completions";
              reasoning = true;
              input = ["text"];
              contextWindow = 1000000;
              maxTokens = 1000000;
              compat.maxTokensField = "max_tokens";
              cost = {
                input = 0.113;
                output = 0.382;
                # Catalogue reports 0.01409999988; rounded, and only the
                # reported per-request cost is billed anyway.
                cacheRead = 0.0141;
                cacheWrite = 0.113;
              };
            }
            {
              # $0.14/$0.28 list, discount 0.05 (billed ~0.95x). Omnimodal
              # (text/image/video/audio) with 1M context and a very cheap
              # cache read, so it is the pick for long cached-context runs.
              id = "XiaomiMiMo/MiMo-V2.6-Flash";
              name = "MiMo V2.6 Flash";
              api = "openai-completions";
              reasoning = true;
              input = ["text" "image"];
              contextWindow = 1048576;
              maxTokens = 1048576;
              compat.maxTokensField = "max_tokens";
              cost = {
                input = 0.14;
                output = 0.28;
                cacheRead = 0.0028;
                cacheWrite = 0.14;
              };
            }
          ];
        };
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
       | .enableInstallTelemetry = false' "$piSettings" > "$piTmp"; then
      mv "$piTmp" "$piSettings"
    else
      rm -f "$piTmp"
      echo "warning: pi settings.json merge failed; left unchanged" >&2
    fi
  '';
}
